#!/usr/bin/env bash
# Is the v3.5.0 gap code or layout? Swaps fasthttp, relinks with other function layouts and scans main's first-parent history.
# shellcheck disable=SC2016 # the backticks are markdown fences for the job summary
set -euo pipefail
export REPO=$PWD DIAG=$PWD/diag WORK=${RUNNER_TEMP:-/tmp}/diag ROUNDS=${ROUNDS:-10} LC_ALL=C
: "${MAIN:?MAIN must name the fast Fiber commit}" "${PLATEAU:?PLATEAU must name the first commit to scan}"
# shellcheck source=diag/lib.sh
source "$DIAG/lib.sh"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}

# compare TITLE REF NAME...: measure the binaries and report their Fiber part against REF
compare() {
  local title=$1 slug=${1// /-} out
  shift
  mapfile -t paths < <(bins "$@")
  measure "${paths[@]}" >"$WORK/raw-$slug.txt"
  out=$(python3 "$DIAG/table.py" "$WORK/raw-$slug.txt" "$@")
  printf '== %s\n%s\n' "$title" "$out"
  printf '%s\n' "$out" >"$WORK/table-$slug.txt"
  printf '### %s\n```text\n%s\n```\n' "$title" "$out" >>"$summary"
}

rm -rf "$WORK"
mkdir -p "$WORK/bin"
git clone --quiet --filter=blob:none "${FIBER_URL:-https://github.com/gofiber/fiber}" "$WORK/fiber"
git -C "$WORK/fiber" worktree add --quiet "$WORK/fiber-v350" v3.5.0
git -C "$WORK/fiber" worktree add --quiet "$WORK/fiber-main" "$MAIN"
go version

module main "$WORK/fiber-main"
module v350 "$WORK/fiber-v350"
module v350-fh174 "$WORK/fiber-v350" v1.74.0
module main-fh173 "$WORK/fiber-main" v1.73.0
for m in main v350 v350-fh174 main-fh173; do binary "$m" "$WORK/mod-$m"; done
binary v2 "$REPO/v2"
for seed in 1 2 3; do
  binary "main-r$seed" "$WORK/mod-main" "-randlayout=$seed"
  binary "v350-r$seed" "$WORK/mod-v350" "-randlayout=$seed"
  binary "v2-r$seed" "$REPO/v2" "-randlayout=$seed"
done
binary main-a32 "$WORK/mod-main" "-funcalign=32"
binary v350-a32 "$WORK/mod-v350" "-funcalign=32"
binary v2-a32 "$REPO/v2" "-funcalign=32"

compare "fasthttp swap" main v350 v350-fh174 main-fh173
compare "function layout" main main-r1 main-r2 main-r3 main-a32 v350 v350-r1 v350-r2 v350-r3 v350-a32 v2 v2-r1 v2-r2 v2-r3 v2-a32

# every first-parent commit from the plateau to main, each with the dependencies it requires
scan=()
for c in $(git -C "$WORK/fiber" rev-list --reverse --first-parent "$PLATEAU^1..$MAIN"); do
  name=c-${c:0:8}
  git -C "$WORK/fiber" checkout --quiet "$c"
  if module "$name" "$WORK/fiber" >"$WORK/build-$name.log" 2>&1 && binary "$name" "$WORK/mod-$name" >>"$WORK/build-$name.log" 2>&1; then
    scan+=("$name")
  else
    echo "$name does not build, left out"
  fi
done
compare "first-parent scan" main "${scan[@]}"
git -C "$WORK/fiber" log --reverse --first-parent --format='c-%h %s' "$PLATEAU^1..$MAIN" | cut -c1-100 | tee "$WORK/scan-commits.txt"
