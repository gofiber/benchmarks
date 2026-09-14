#!/usr/bin/env bash
set -euo pipefail
# awk has to read decimal points, whatever the locale
export LC_ALL=C

count=${COUNT:-10}
benchtime=${BENCHTIME:-500ms}
benchstat=golang.org/x/perf/cmd/benchstat@v0.0.0-20260825160852-19be9d8e6c70

cd "$(dirname "$0")"
# both versions must be timed by the same harness
cmp v2/harness_test.go v3/harness_test.go

rm -rf results
mkdir results
for v in v2 v3; do
  (cd "$v" && go test -c -o "../results/$v.test")
  "results/$v.test" -test.run '^$' -test.bench . -test.benchtime 1x -test.cpu 1 |
    sed -n 's|^BenchmarkRequest/\([^[:space:]]*\).*|\1|p' >"results/$v.names"
done
cmp results/v2.names results/v3.names
names=()
while IFS= read -r name; do names+=("$name"); done <results/v2.names

# busy, stolen and idle ticks of the whole machine
ticks() { awk '$1 == "cpu" {print $2 + $3 + $4 + $7 + $8, $9, $5 + $6}' /proc/stat; }

# rounds FROM TO: v2 and v3 of a scenario run back to back in alternating order,
# so host load lasting seconds hits both sides of a pair and cancels in their ratio
rounds() {
  local i j v pair busy steal idle busy2 steal2 idle2
  for ((i = $1; i < $2; i++)); do
    if [[ -r /proc/stat ]]; then read -r busy steal idle < <(ticks); fi
    for j in "${!names[@]}"; do
      pair=(v2 v3)
      if (((i + j) % 2)); then pair=(v3 v2); fi
      for v in "${pair[@]}"; do
        "results/$v.test" -test.run '^$' -test.bench "^BenchmarkRequest\$/^${names[j]}\$" \
          -test.benchtime "$benchtime" -test.cpu 1 >>"results/$v.txt"
      done
    done
    # logged, not gated on: it only tells disturbed rounds apart afterwards
    if [[ -r /proc/stat ]]; then
      read -r busy2 steal2 idle2 < <(ticks)
      echo "round $i: $((busy2 - busy)) busy, $((steal2 - steal)) stolen, $((idle2 - idle)) idle ticks" >>results/cpu.txt
    fi
  done
}

total=$count
rounds 0 "$total"
python3 paired.py results >results/paired.txt
# a noisy run gets as many rounds again: pairs cancel host load, so more of them narrow the interval
if awk -v noise="$(<results/noise)" 'BEGIN { exit !(noise != "null" && noise >= 5) }'; then
  echo "median interval ±$(<results/noise)% after $count rounds, running $count more"
  total=$((2 * count))
  rounds "$count" "$total"
  python3 paired.py results >results/paired.txt
fi
cat results/paired.txt

# the two modules differ only in their import path
go run "$benchstat" -ignore pkg v2=results/v2.txt v3=results/v3.txt | tee results/benchstat.txt
go run "$benchstat" -ignore pkg -format csv v2=results/v2.txt v3=results/v3.txt >results/benchstat.csv

# what was compared, for the results page
printf '{"v2":"%s","v3":"%s","go":"%s","cpu":"%s","date":"%s","rounds":%d,"noise":%s}\n' \
  "$(cd v2 && go list -m -f '{{.Version}}' github.com/gofiber/fiber/v2)" \
  "$(cd v3 && go list -m -f '{{.Version}}' github.com/gofiber/fiber/v3)" \
  "$(go version results/v2.test | sed 's/.*: //')" \
  "$(sed -n '/^cpu: /{s/^cpu: *//;s/ *$//;p;q;}' results/v2.txt)" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$total" \
  "$(<results/noise)" >results/meta.json
