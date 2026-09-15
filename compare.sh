#!/usr/bin/env bash
set -euo pipefail
# awk has to read decimal points, whatever the locale
export LC_ALL=C

count=${COUNT:-10}
benchtime=${BENCHTIME:-500ms}
benchstat=golang.org/x/perf/cmd/benchstat@v0.0.0-20260825160852-19be9d8e6c70
# id=module builds the module's go.mod pin, id=module@ref that Fiber ref; the first target is the baseline
targets=(v2=v2 v3.0.0=v3@v3.0.0 v3=v3 main=v3@main)

cd "$(dirname "$0")"
root=$PWD
# every target must be timed by the same harness
cmp v2/harness_test.go v3/harness_test.go

rm -rf results
mkdir results
ids=()
versions=()
for target in "${targets[@]}"; do
  id=${target%%=*}
  module=${target#*=}
  dir=$module
  if [[ $module == *@* ]]; then
    ref=${module#*@}
    module=${module%@*}
    # a fresh module resolves the ref with the dependencies that Fiber version ships with
    dir=results/build/$id
    mkdir -p "$dir"
    cp "$module"/*_test.go "$dir"
    printf 'module github.com/gofiber/benchmarks/%s\n\n%s\n' "$module" "$(awk '$1 == "go"' "$module/go.mod")" >"$dir/go.mod"
    (cd "$dir" && go get "github.com/gofiber/fiber/$module@$ref" && go mod tidy)
  fi
  (cd "$dir" && go test -c -o "$root/results/$id.test")
  ids+=("$id")
  versions+=("$(cd "$dir" && go list -m -f '{{.Version}}' "github.com/gofiber/fiber/$module")")
  "results/$id.test" -test.run '^$' -test.bench . -test.benchtime 1x -test.cpu 1 |
    sed -n 's|^BenchmarkRequest/\([^[:space:]]*\).*|\1|p' >"results/$id.names"
done
for id in "${ids[@]:1}"; do cmp "results/${ids[0]}.names" "results/$id.names"; done
names=()
while IFS= read -r name; do names+=("$name"); done <"results/${ids[0]}.names"

# busy, stolen and idle ticks of the whole machine
ticks() { awk '$1 == "cpu" {print $2 + $3 + $4 + $7 + $8, $9, $5 + $6}' /proc/stat; }

# rounds FROM TO: all targets of a scenario run back to back in rotating order,
# so host load lasting seconds hits every side of a comparison and cancels in the ratios
rounds() {
  local i j k id busy steal idle busy2 steal2 idle2
  for ((i = $1; i < $2; i++)); do
    if [[ -r /proc/stat ]]; then read -r busy steal idle < <(ticks); fi
    for j in "${!names[@]}"; do
      for ((k = 0; k < ${#ids[@]}; k++)); do
        id=${ids[(i + j + k) % ${#ids[@]}]}
        "results/$id.test" -test.run '^$' -test.bench "^BenchmarkRequest\$/^${names[j]}\$" \
          -test.benchtime "$benchtime" -test.cpu 1 >>"results/$id.txt"
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
python3 paired.py results "${ids[@]}" >results/paired.txt
# a noisy run gets as many rounds again: pairs cancel host load, so more of them narrow the interval
if awk -v noise="$(<results/noise)" 'BEGIN { exit !(noise != "null" && noise >= 5) }'; then
  echo "median interval ±$(<results/noise)% after $count rounds, running $count more"
  total=$((2 * count))
  rounds "$count" "$total"
  python3 paired.py results "${ids[@]}" >results/paired.txt
fi
cat results/paired.txt

# the modules differ only in their import path
columns=()
for id in "${ids[@]}"; do columns+=("$id=results/$id.txt"); done
go run "$benchstat" -ignore pkg "${columns[@]}" | tee results/benchstat.txt
go run "$benchstat" -ignore pkg -format csv "${columns[@]}" >results/benchstat.csv

# what was compared, for the results page
list=()
for i in "${!ids[@]}"; do list+=("{\"id\":\"${ids[i]}\",\"version\":\"${versions[i]}\"}"); done
printf '{"targets":[%s],"go":"%s","cpu":"%s","date":"%s","rounds":%d,"noise":%s}\n' \
  "$(IFS=,; echo "${list[*]}")" \
  "$(go version "results/${ids[0]}.test" | sed 's/.*: //')" \
  "$(sed -n '/^cpu: /{s/^cpu: *//;s/ *$//;p;q;}' "results/${ids[0]}.txt")" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$total" \
  "$(<results/noise)" >results/meta.json
