#!/usr/bin/env bash
# Where did fasthttp's request parsing get more expensive? Every release from 1.51 to 1.74, each with several function layouts.
# shellcheck disable=SC2016 # the backticks are markdown fences for the job summary
set -euo pipefail
export DIAG=$PWD/diag WORK=${RUNNER_TEMP:-/tmp}/diag ROUNDS=${ROUNDS:-6} LC_ALL=C
# shellcheck source=diag/lib.sh
source "$DIAG/lib.sh"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
versions=${VERSIONS:-$(seq 51 74 | awk '{print "1." $1 ".0"}')}
layouts=${LAYOUTS:-4}

rm -rf "$WORK"
mkdir -p "$WORK/bin"
go version
names=()
for version in $versions; do
  if ! fhmodule "$version" >"$WORK/build-$version.log" 2>&1; then
    echo "$version does not resolve, left out"
    continue
  fi
  for ((l = 0; l < layouts; l++)); do
    flags=""
    [[ $l -gt 0 ]] && flags="-randlayout=$l"
    if binary "$version-l$l" "$WORK/mod-$version" "$flags" >>"$WORK/build-$version.log" 2>&1; then
      names+=("$version-l$l")
    else
      echo "$version layout $l does not build, left out"
    fi
  done
done
echo "measuring ${#names[@]} binaries over $ROUNDS rounds"

mapfile -t paths < <(bins "${names[@]}")
measure "${paths[@]}" >"$WORK/raw-versions.txt"
out=$(python3 "$DIAG/versions.py" "$WORK/raw-versions.txt")
printf '%s\n' "$out" | tee "$WORK/table-versions.txt"
printf '### fasthttp release by release\n```text\n%s\n```\n' "$out" >>"$summary"
