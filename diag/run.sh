#!/usr/bin/env bash
# Does the host fast path pay off on this runner? valyala/fasthttp master against the branch, each in several function layouts.
# shellcheck disable=SC2016 # the backticks are markdown fences for the job summary
set -euo pipefail
export DIAG=$PWD/diag WORK=${RUNNER_TEMP:-/tmp}/diag ROUNDS=${ROUNDS:-8} LC_ALL=C
: "${OPT_REPO:?OPT_REPO must name the fork}" "${OPT_REF:?OPT_REF must name the branch}"
# shellcheck source=diag/lib.sh
source "$DIAG/lib.sh"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}

rm -rf "$WORK"
mkdir -p "$WORK/bin"
git clone --quiet --filter=blob:none https://github.com/valyala/fasthttp "$WORK/base"
git clone --quiet --filter=blob:none "$OPT_REPO" "$WORK/opt"
git -C "$WORK/opt" checkout --quiet "$OPT_REF"
echo "base $(git -C "$WORK/base" log --oneline -1)"
echo "opt  $(git -C "$WORK/opt" log --oneline -1)"
go version

names=()
for variant in base opt; do
  dir=$WORK/mod-$variant
  mkdir -p "$dir"
  cp "$DIAG/floor_test.go" "$dir"
  printf 'module floor\n\ngo 1.27.0\n\nrequire github.com/valyala/fasthttp v1.74.0\n\nreplace github.com/valyala/fasthttp => %s\n' "$WORK/$variant" >"$dir/go.mod"
  (cd "$dir" && go mod tidy)
  for l in 0 1 2 3; do
    flags=""
    ((l == 0)) || flags="-randlayout=$l"
    binary "$variant-l$l" "$dir" "$flags"
    names+=("$variant-l$l")
  done
done

mapfile -t paths < <(bins "${names[@]}")
measure "${paths[@]}" >"$WORK/raw-fastpath.txt"
out=$(python3 "$DIAG/compare2.py" "$WORK/raw-fastpath.txt")
printf '%s\n' "$out" | tee "$WORK/table-fastpath.txt"
printf '### host fast path\n```text\n%s\n```\n' "$out" >>"$summary"

# where the server path spends its time on this runner, for the parts the fast path does not touch
for variant in base opt; do
  "$WORK/bin/$variant-l0.test" -test.run '^$' -test.bench '^BenchmarkRequest$/^serve_conn$' -test.benchtime 10s -test.cpu 1 \
    -test.cpuprofile "$WORK/$variant.prof" >/dev/null
  echo "== profile $variant"
  go tool pprof -top -nodecount 20 "$WORK/bin/$variant-l0.test" "$WORK/$variant.prof" | tee "$WORK/top-$variant.txt"
done
printf '### server path profile, master\n```text\n%s\n```\n' "$(cat "$WORK/top-base.txt")" >>"$summary"
