# shellcheck shell=bash
# fhmodule VERSION: a module with only the floor benchmark against that fasthttp release
fhmodule() {
  local dir=$WORK/mod-$1
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$DIAG/floor_test.go" "$dir"
  printf 'module floor\n\ngo 1.27.0\n\nrequire github.com/valyala/fasthttp v%s\n' "$1" >"$dir/go.mod"
  (cd "$dir" && go mod tidy)
}

# binary NAME MODULE_DIR [LDFLAGS]: link the benchmark, LDFLAGS can change the function layout
binary() {
  (cd "$2" && go test -c -ldflags="${3:-}" -o "$WORK/bin/$1.test" .)
}

# bins NAME...: binary paths for measure
bins() {
  local name
  for name in "$@"; do printf '%s\n' "$WORK/bin/$name.test"; done
}

# measure BIN...: both benchmarks of every binary per round in rotating order, as "round name benchmark ns" lines
measure() {
  local i k b n=$#
  local all=("$@")
  for ((i = 0; i < ROUNDS; i++)); do
    for ((k = 0; k < n; k++)); do
      b=${all[(i + k) % n]}
      "$b" -test.run '^$' -test.bench . -test.benchtime 200ms -test.cpu 1 |
        awk -v i="$i" -v name="$(basename "$b" .test)" '/^BenchmarkRequest\// {for (f = 2; f <= NF; f++) if ($f == "ns/op") print i, name, $1, $(f - 1)}'
    done
  done
}
