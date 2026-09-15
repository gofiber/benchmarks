#!/usr/bin/env bash
# Profiles v2, v3.5.0 and main, checks the v3.5.0 routing gap against main and bisects the commit that removed it.
# shellcheck disable=SC2016 # the backticks are markdown fences for the job summary
set -euo pipefail
export REPO=$PWD DIAG=$PWD/diag WORK=${RUNNER_TEMP:-/tmp}/diag ROUNDS=${ROUNDS:-10} LC_ALL=C
: "${MAIN:?MAIN must name the fast Fiber commit}"
# shellcheck source=diag/lib.sh
source "$DIAG/lib.sh"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
fenced() { printf '```text\n%s\n```\n' "$1" >>"$summary"; }

rm -rf "$WORK"
mkdir -p "$WORK/bin"
git clone --quiet --filter=blob:none "${FIBER_URL:-https://github.com/gofiber/fiber}" "$WORK/fiber"
git -C "$WORK/fiber" worktree add --quiet "$WORK/fiber-v350" v3.5.0
git -C "$WORK/fiber" worktree add --quiet "$WORK/fiber-main" "$MAIN"
(cd "$REPO/v2" && go test -c -o "$WORK/bin/v2.test" .)
build v350 "$WORK/fiber-v350"
build main "$WORK/fiber-main"
go version

echo "== endpoints"
measure "$WORK/bin/v2.test" "$WORK/bin/v350.test" "$WORK/bin/main.test" >"$WORK/raw-endpoints.txt"
reproduced=0
endpoints=$(python3 "$DIAG/gap.py" "$WORK/raw-endpoints.txt" v350 main "${MIN_GAP:-30}" endpoints) || reproduced=$?
echo "$endpoints"
fenced "$endpoints"

# where each version spends a routed request and the bare fasthttp parse
for bench in static fasthttp_floor; do
  for name in v2 v350 main; do
    echo "== profile $name $bench"
    "$WORK/bin/$name.test" -test.run '^$' -test.bench "^BenchmarkRequest\$/^$bench\$" -test.benchtime "${PROFILE_TIME:-10s}" -test.cpu 1 \
      -test.cpuprofile "$WORK/$name-$bench.prof" >/dev/null
    go tool pprof -top -nodecount 35 "$WORK/bin/$name.test" "$WORK/$name-$bench.prof" | tee "$WORK/top-$name-$bench.txt"
  done
done
echo "== static, v350 minus main"
go tool pprof -top -nodecount 25 -diff_base "$WORK/main-static.prof" "$WORK/bin/v350.test" "$WORK/v350-static.prof" | tee "$WORK/top-v350-minus-main.txt"
fenced "$(cat "$WORK/top-v350-minus-main.txt")"

if ((reproduced != 0)); then
  echo "the gap does not reproduce here, nothing to bisect"
  exit 1
fi
gap=$(sed -n 's/.*gap \([+-][0-9.]*\) ns.*/\1/p' <<<"$endpoints")
THRESHOLD=$(awk -v g="$gap" 'BEGIN {print g / 2}')
export THRESHOLD

echo "== bisect with a threshold of $THRESHOLD ns"
cd "$WORK/fiber"
git bisect start --first-parent --term-old=slow --term-new=fast "$MAIN" v3.5.0
git bisect run "$DIAG/step.sh" | tee "$WORK/bisect.txt"
first=$(git rev-parse refs/bisect/fast)
{
  git show --no-patch --format='first fast commit: %h %s (%an, %ad)' "$first"
  if git rev-parse -q --verify "$first^2" >/dev/null; then
    echo "commits it merged:"
    git log --oneline "$first^1..$first^2"
  fi
  git diff --stat "$first^1" "$first" | tail -25
} | tee "$WORK/result.txt"
fenced "$(cat "$WORK/result.txt")"
git bisect log >"$WORK/bisect-log.txt"
git bisect reset >/dev/null
