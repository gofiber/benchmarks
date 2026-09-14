#!/usr/bin/env bash
set -euo pipefail

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
done

# interleaved and alternating, so host drift hits both versions alike
for ((i = 0; i < count; i++)); do
  pair=(v2 v3)
  if ((i % 2)); then pair=(v3 v2); fi
  for v in "${pair[@]}"; do
    "results/$v.test" -test.run '^$' -test.bench . -test.benchtime "$benchtime" -test.cpu 1 >>"results/$v.txt"
  done
done

# the two modules differ only in their import path
go run "$benchstat" -ignore pkg v2=results/v2.txt v3=results/v3.txt | tee results/benchstat.txt
go run "$benchstat" -ignore pkg -format csv v2=results/v2.txt v3=results/v3.txt >results/benchstat.csv

# what was compared, for the results page
printf '{"v2":"%s","v3":"%s","go":"%s","cpu":"%s","date":"%s"}\n' \
  "$(cd v2 && go list -m -f '{{.Version}}' github.com/gofiber/fiber/v2)" \
  "$(cd v3 && go list -m -f '{{.Version}}' github.com/gofiber/fiber/v3)" \
  "$(go version results/v2.test | sed 's/.*: //')" \
  "$(sed -n '/^cpu: /{s/^cpu: *//;s/ *$//;p;q;}' results/v2.txt)" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >results/meta.json
