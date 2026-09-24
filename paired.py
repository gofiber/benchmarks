#!/usr/bin/env python3
# Paired sec/op of each target against the baseline: median of per-round ratios with a sign-test confidence interval.
import csv
import json
import math
import re
import statistics
import sys
from pathlib import Path

LINE = re.compile(r"^BenchmarkRequest/(\S+?)(?:-\d+)?\s+\d+\s+([\d.]+) ns/op")


def load(path):
    samples = {}
    for line in Path(path).read_text().splitlines():
        if m := LINE.match(line):
            samples.setdefault(m[1], []).append(float(m[2]))
    return samples


def sign_ci(xs, confidence=0.95):
    # order statistics of the sign test, no assumption about the noise distribution
    xs, n = sorted(xs), len(xs)
    tail, k = 0.0, 0
    while tail + math.comb(n, k) / 2**n <= (1 - confidence) / 2:
        tail += math.comb(n, k) / 2**n
        k += 1
    # None below 6 rounds at 95%
    return (xs[k - 1], xs[n - k], 1 - 2 * tail) if k else None


def duration(ns):
    for unit, scale in (("s", 1e9), ("ms", 1e6), ("µs", 1e3)):
        if ns >= scale:
            return f"{ns / scale:#.4g}{unit}"
    return f"{ns:#.4g}ns"


def main(results, ids):
    base, *targets = ids
    samples = {i: load(Path(results, f"{i}.txt")) for i in ids}
    if not samples[base] or any(samples[t].keys() != samples[base].keys() for t in targets):
        sys.exit(f"{', '.join(ids)} must run the same, non-empty set of scenarios")
    rows = []
    for target in targets:
        for name, before in samples[base].items():
            after = samples[target][name]
            if len(before) != len(after):
                sys.exit(f"{name}: {len(before)} {base} samples but {len(after)} {target} samples")
            # the n-th sample of each target was measured in the same round
            ratios = [a / b for b, a in zip(before, after)]
            ci = sign_ci(ratios)
            rows.append({
                "target": target,
                "name": name,
                "base": statistics.median(before) / 1e9,
                "value": statistics.median(after) / 1e9,
                "delta": (statistics.median(ratios) - 1) * 100,
                "lo": (ci[0] - 1) * 100 if ci else None,
                "hi": (ci[1] - 1) * 100 if ci else None,
                "rounds": len(ratios),
                "confidence": round(ci[2], 4) if ci else None,
                "significant": bool(ci) and (ci[0] > 1 or ci[1] < 1),
            })

    with open(Path(results, "paired.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)

    width = max(len(r["name"]) for r in rows)
    column = max(len(i) for i in ids) + len(" sec/op")
    for target in targets:
        print(f"{'':{width}}  {base + ' sec/op':>{column}}  {target + ' sec/op':>{column}}  {target} vs {base}, paired")
        for r in rows:
            if r["target"] != target:
                continue
            if r["lo"] is None:
                change = f"{r['delta']:+.2f}% [no interval]"
            else:
                delta = f"{r['delta']:+.2f}%" if r["significant"] else "~"
                change = f"{delta:>8} [{r['lo']:+.1f}%, {r['hi']:+.1f}%]"
            print(f"{r['name']:{width}}  {duration(r['base'] * 1e9):>{column}}  {duration(r['value'] * 1e9):>{column}}  {change}")
        print()
    if rows[0]["lo"] is None:
        print(f"no intervals: {rows[0]['rounds']} rounds, a 95% interval needs at least 6")
        noise = None
    else:
        # the page leaves the baseline out as well
        noise = round(statistics.median((r["hi"] - r["lo"]) / 2 for r in rows if r["name"] != "fasthttp_only"), 1)
        print(f"median interval ±{noise}% without fasthttp_only, {sum(r['significant'] for r in rows)} of {len(rows)} significant, "
              f"{rows[0]['rounds']} rounds, {rows[0]['confidence']:.1%} sign-test confidence")
    # compare.sh extends a noisy run by it, the page reads it from meta.json
    Path(results, "noise").write_text(f"{json.dumps(noise)}\n")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit("usage: paired.py RESULTS BASELINE TARGET...")
    main(sys.argv[1], sys.argv[2:])
