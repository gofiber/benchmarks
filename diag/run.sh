#!/usr/bin/env bash
# Does the host fast path pay off on this runner? valyala/fasthttp master against the branch, each in several function layouts.
# shellcheck disable=SC2016 # the backticks are markdown fences for the job summary
set -euo pipefail
export DIAG=$PWD/diag WORK=${RUNNER_TEMP:-/tmp}/diag ROUNDS=${ROUNDS:-8} LC_ALL=C
: "${OPT_REPO:?OPT_REPO must name the fork}" "${VARIANTS:?VARIANTS must list name:ref pairs}"
# shellcheck source=diag/lib.sh
source "$DIAG/lib.sh"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}

rm -rf "$WORK"
mkdir -p "$WORK/bin"
git clone --quiet --filter=blob:none https://github.com/valyala/fasthttp "$WORK/base"
git clone --quiet --filter=blob:none "$OPT_REPO" "$WORK/fork"
echo "base $(git -C "$WORK/base" log --oneline -1)"
go version

# build the baseline and every named branch of the fork, each in several function layouts
names=()
build_variant() { # build_variant NAME SOURCE_DIR
  local dir=$WORK/mod-$1 l flags
  mkdir -p "$dir"
  cp "$DIAG/floor_test.go" "$dir"
  printf 'module floor\n\ngo 1.27.0\n\nrequire github.com/valyala/fasthttp v1.74.0\n\nreplace github.com/valyala/fasthttp => %s\n' "$2" >"$dir/go.mod"
  (cd "$dir" && go mod tidy)
  for l in 0 1 2 3; do
    flags=""
    ((l == 0)) || flags="-randlayout=$l"
    binary "$1-l$l" "$dir" "$flags"
    names+=("$1-l$l")
  done
}
build_variant base "$WORK/base"
for pair in $VARIANTS; do
  git -C "$WORK/fork" checkout --quiet "${pair#*:}"
  echo "${pair%%:*} $(git -C "$WORK/fork" log --oneline -1)"
  build_variant "${pair%%:*}" "$WORK/fork"
done

mapfile -t paths < <(bins "${names[@]}")
measure "${paths[@]}" >"$WORK/raw-fastpath.txt"
mapfile -t reported < <(printf '%s\n' base; for pair in $VARIANTS; do printf '%s\n' "${pair%%:*}"; done)
out=$(python3 "$DIAG/compare2.py" "$WORK/raw-fastpath.txt" "${reported[@]}")
printf '%s\n' "$out" | tee "$WORK/table-fastpath.txt"
printf '### host fast path\n```text\n%s\n```\n' "$out" >>"$summary"

# where the server path spends its time on this runner, for the parts the fast path does not touch
"$WORK/bin/base-l0.test" -test.run '^$' -test.bench '^BenchmarkRequest$/^serve_conn$' -test.benchtime 10s -test.cpu 1 \
  -test.cpuprofile "$WORK/base.prof" >/dev/null
echo "== profile base"
go tool pprof -top -nodecount 20 "$WORK/bin/base-l0.test" "$WORK/base.prof" | tee "$WORK/top-base.txt"
printf '### server path profile, master\n```text\n%s\n```\n' "$(cat "$WORK/top-base.txt")" >>"$summary"
