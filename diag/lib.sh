# shellcheck shell=bash
# module NAME FIBER_DIR [FASTHTTP]: a v3 benchmark module against the Fiber checkout in FIBER_DIR, optionally on another fasthttp
module() {
  local dir=$WORK/mod-$1
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$REPO"/v3/*_test.go "$dir"
  printf 'module github.com/gofiber/benchmarks/v3\n\ngo 1.27.0\n\nrequire github.com/gofiber/fiber/v3 v3.0.0\n\nreplace github.com/gofiber/fiber/v3 => %s\n' "$2" >"$dir/go.mod"
  if [[ -n ${3:-} ]]; then
    printf 'replace github.com/valyala/fasthttp => github.com/valyala/fasthttp %s\n' "$3" >>"$dir/go.mod"
  fi
  (cd "$dir" && go mod tidy)
}

# binary NAME MODULE_DIR [LDFLAGS]: link the benchmark binary, LDFLAGS can change the function layout
binary() {
  (cd "$2" && go test -c -ldflags="${3:-}" -o "$WORK/bin/$1.test" .)
}

# bins NAME...: binary paths for measure
bins() {
  local name
  for name in "$@"; do printf '%s\n' "$WORK/bin/$name.test"; done
}

# measure BIN...: fasthttp_floor and static of every binary per round in rotating order, as "round name benchmark ns" lines
measure() {
  local i k s b n=$#
  local all=("$@")
  for ((i = 0; i < ROUNDS; i++)); do
    for s in fasthttp_floor static; do
      for ((k = 0; k < n; k++)); do
        b=${all[(i + k) % n]}
        "$b" -test.run '^$' -test.bench "^BenchmarkRequest\$/^$s\$" -test.benchtime 200ms -test.cpu 1 |
          awk -v i="$i" -v name="$(basename "$b" .test)" '/^BenchmarkRequest\// {for (f = 2; f <= NF; f++) if ($f == "ns/op") print i, name, $1, $(f - 1)}'
      done
    done
  done
}
