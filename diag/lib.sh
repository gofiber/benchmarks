# shellcheck shell=bash
# build NAME FIBER_DIR: the v3 benchmark binary against the Fiber checkout in FIBER_DIR, with the dependencies it requires
build() {
  local dir=$WORK/mod-$1
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$REPO"/v3/*_test.go "$dir"
  printf 'module github.com/gofiber/benchmarks/v3\n\ngo 1.27.0\n\nrequire github.com/gofiber/fiber/v3 v3.0.0\n\nreplace github.com/gofiber/fiber/v3 => %s\n' "$2" >"$dir/go.mod"
  (cd "$dir" && go mod tidy && go test -c -o "$WORK/bin/$1.test" .)
}

# measure BIN...: fasthttp_floor and static of every binary per round in rotating order, as "round name benchmark ns" lines
measure() {
  local i k s b n=$#
  local bins=("$@")
  for ((i = 0; i < ROUNDS; i++)); do
    for s in fasthttp_floor static; do
      for ((k = 0; k < n; k++)); do
        b=${bins[(i + k) % n]}
        "$b" -test.run '^$' -test.bench "^BenchmarkRequest\$/^$s\$" -test.benchtime 200ms -test.cpu 1 |
          awk -v i="$i" -v name="$(basename "$b" .test)" '/^BenchmarkRequest\// {for (f = 2; f <= NF; f++) if ($f == "ns/op") print i, name, $1, $(f - 1)}'
      done
    done
  done
}
