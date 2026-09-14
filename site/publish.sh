#!/usr/bin/env bash
# Adds one compare.sh result to the results site: publish.sh <results-dir> <site-dir>
set -euo pipefail

results=$1
site=$2
id=${RUN_ID:?RUN_ID must name the run}

mkdir -p "$site/data/$id"
cp "$results/benchstat.csv" "$results/benchstat.txt" "$results/paired.csv" "$site/data/$id/"
cp "$(dirname "$0")/index.html" "$site/index.html"
touch "$site/.nojekyll"

index=$site/data/index.json
[[ -f $index ]] || echo '[]' >"$index"
# newest first; a re-run of the same run replaces its entry
jq --arg id "$id" --arg url "${RUN_URL:-}" --arg sha "${SHA:-}" --slurpfile meta "$results/meta.json" \
  '[$meta[0] + {id: $id, url: $url, sha: $sha}] + map(select(.id != $id))' "$index" >"$index.tmp"
mv "$index.tmp" "$index"
