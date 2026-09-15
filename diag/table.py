#!/usr/bin/env python3
# table.py RAW REF NAME...: median fasthttp_floor, Fiber part (static minus floor) and the paired part difference to REF per binary
import statistics
import sys
from collections import defaultdict

raw, ref, names = sys.argv[1], sys.argv[2], sys.argv[3:]
names = [ref] + [n for n in names if n != ref]
runs = defaultdict(dict)
for line in open(raw):
    rnd, name, bench, ns = line.split()
    runs[name, rnd][bench.split("/")[1]] = float(ns)
part, floor = defaultdict(dict), defaultdict(list)
for (name, rnd), d in runs.items():
    if {"static", "fasthttp_floor"} <= d.keys():
        part[name][rnd] = d["static"] - d["fasthttp_floor"]
        floor[name].append(d["fasthttp_floor"])
print(f"{'binary':<14} {'floor':>7} {'part':>7} {'part vs ' + ref:>14}")
for name in names:
    rounds = [r for r in part[name] if r in part[ref]]
    if not rounds:
        print(f"{name:<14} no data")
        continue
    diff = statistics.median(part[name][r] - part[ref][r] for r in rounds)
    print(f"{name:<14} {statistics.median(floor[name]):7.1f} {statistics.median(part[name].values()):7.1f} {diff:+14.1f}")
