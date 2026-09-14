#!/usr/bin/env python3
# Paired v3 vs v2 sec/op: median of per-round ratios with a sign-test confidence interval.
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


def main(results):
    v2, v3 = load(Path(results, "v2.txt")), load(Path(results, "v3.txt"))
    if not v2 or v2.keys() != v3.keys():
        sys.exit("v2 and v3 must run the same, non-empty set of scenarios")
    rows = []
    for name in v2:
        if len(v2[name]) != len(v3[name]):
            sys.exit(f"{name}: {len(v2[name])} v2 samples but {len(v3[name])} v3 samples")
        # the n-th sample of each version was measured in the same round
        ratios = [b / a for a, b in zip(v2[name], v3[name])]
        ci = sign_ci(ratios)
        rows.append({
            "name": name,
            "v2": statistics.median(v2[name]) / 1e9,
            "v3": statistics.median(v3[name]) / 1e9,
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
    print(f"{'':{width}}  {'v2 sec/op':>10}  {'v3 sec/op':>10}  v3 vs v2, paired")
    for r in rows:
        if r["lo"] is None:
            change = f"{r['delta']:+.2f}% [no interval]"
        else:
            delta = f"{r['delta']:+.2f}%" if r["significant"] else "~"
            change = f"{delta:>8} [{r['lo']:+.1f}%, {r['hi']:+.1f}%]"
        print(f"{r['name']:{width}}  {duration(r['v2'] * 1e9):>10}  {duration(r['v3'] * 1e9):>10}  {change}")
    if rows[0]["lo"] is None:
        print(f"no intervals: {rows[0]['rounds']} rounds, a 95% interval needs at least 6")
        noise = None
    else:
        # the page leaves the baseline out as well
        noise = round(statistics.median((r["hi"] - r["lo"]) / 2 for r in rows if r["name"] != "fasthttp_floor"), 1)
        print(f"median interval ±{noise}% without fasthttp_floor, {sum(r['significant'] for r in rows)} of {len(rows)} significant, "
              f"{rows[0]['rounds']} rounds, {rows[0]['confidence']:.1%} sign-test confidence")
    # compare.sh extends a noisy run by it, the page reads it from meta.json
    Path(results, "noise").write_text(f"{json.dumps(noise)}\n")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "results")
