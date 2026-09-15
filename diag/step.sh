#!/usr/bin/env bash
# git bisect run step: exit 0 while the checkout is slow like v3.5.0, 1 once it is fast like main, 125 if it does not build
set -uo pipefail
# shellcheck source=diag/lib.sh
source "$DIAG/lib.sh"
commit=$(git rev-parse --short HEAD)
if ! build x "$PWD" >"$WORK/build-$commit.log" 2>&1; then
  echo "step $commit: does not build, skipped"
  exit 125
fi
measure "$WORK/bin/x.test" "$WORK/bin/main.test" >"$WORK/raw-$commit.txt"
python3 "$DIAG/gap.py" "$WORK/raw-$commit.txt" x main "$THRESHOLD" "step $commit"
