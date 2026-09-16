#!/usr/bin/env python3
# compare2.py RAW NAME...: per variant the mean over layouts of the per-layout medians, and the difference to the first
# name with a Welch 95% interval. Layout, not repetition, dominates the variance here, so the sample size is the number
# of layouts.
import math
import statistics
import sys
from collections import defaultdict

# two sided 95% t quantiles, the next lower degrees of freedom is used, which errs wide
T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
       12: 2.179, 15: 2.131, 20: 2.086, 24: 2.064, 30: 2.042, 40: 2.021, 60: 2.000, 120: 1.980, 1000: 1.962}


def t95(df):
    return T95[max(k for k in T95 if k <= max(df, 1))]


def welch(a, b):
    na, nb = len(a), len(b)
    va, vb = statistics.variance(a) / na, statistics.variance(b) / nb
    diff = statistics.fmean(a) - statistics.fmean(b)
    se = math.sqrt(va + vb)
    df = (va + vb) ** 2 / (va**2 / (na - 1) + vb**2 / (nb - 1))
    half = t95(int(df)) * se
    return diff, half


raw, names = sys.argv[1], sys.argv[2:]
samples = defaultdict(list)
for line in open(raw):
    rnd, name, bench, ns = line.split()
    variant, layout = name.rsplit("-", 1)
    samples[variant, bench.split("/")[1], layout].append(float(ns))
per_layout = defaultdict(list)
for (variant, bench, _), values in samples.items():
    per_layout[variant, bench].append(statistics.median(values))

base = names[0]
print(f"{'benchmark':<16} {'variant':<6} {'layouts':>7} {'mean':>8} {'min':>8} {'max':>8} {'change vs ' + base:>30}")
for bench in sorted({b for _, b in per_layout}):
    reference = per_layout[base, bench]
    for name in names:
        values = sorted(per_layout[name, bench])
        if not values:
            print(f"{bench:<16} {name:<6} no data")
            continue
        change = ""
        if name != base:
            diff, half = welch(values, reference)
            percent = 100 * diff / statistics.fmean(reference)
            change = f"{diff:+7.1f} ns [{diff - half:+7.1f}, {diff + half:+7.1f}] {percent:+5.1f}%"
        print(f"{bench:<16} {name:<6} {len(values):7d} {statistics.fmean(values):8.1f} {values[0]:8.1f} {values[-1]:8.1f} {change:>30}")
