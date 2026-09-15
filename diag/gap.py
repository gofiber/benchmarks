#!/usr/bin/env python3
# gap.py RAW TARGET REF THRESHOLD LABEL: median Fiber part (static minus fasthttp_floor per round); exit 0 when TARGET is THRESHOLD ns or more slower than REF
import statistics
import sys
from collections import defaultdict

raw, target, ref, threshold, label = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5]
runs = defaultdict(dict)
for line in open(raw):
    rnd, name, bench, ns = line.split()
    runs[rnd, name][bench.split("/")[1]] = float(ns)
parts, floors = defaultdict(list), defaultdict(list)
for (_, name), d in runs.items():
    if {"static", "fasthttp_floor"} <= d.keys():
        parts[name].append(d["static"] - d["fasthttp_floor"])
        floors[name].append(d["fasthttp_floor"])
median = {name: statistics.median(p) for name, p in parts.items()}
detail = ", ".join(f"{name} part {median[name]:.1f} floor {statistics.median(floors[name]):.1f}" for name in sorted(median))
gap = median[target] - median[ref]
slow = gap >= threshold
print(f"{label}: {detail}; gap {gap:+.1f} ns -> {'slow' if slow else 'fast'}")
sys.exit(0 if slow else 1)
