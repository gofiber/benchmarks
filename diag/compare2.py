#!/usr/bin/env python3
# compare2.py RAW: median per variant and benchmark over all layouts, and the difference between them
import statistics
import sys
from collections import defaultdict

values = defaultdict(list)
for line in open(sys.argv[1]):
    rnd, name, bench, ns = line.split()
    values[name.split("-")[0], bench.split("/")[1]].append(float(ns))
print(f"{'benchmark':<16} {'base':>9} {'opt':>9} {'change':>20}")
for bench in sorted({b for _, b in values}):
    base, opt = statistics.median(values["base", bench]), statistics.median(values["opt", bench])
    print(f"{bench:<16} {base:9.1f} {opt:9.1f} {opt - base:+10.1f} ns ({(opt / base - 1) * 100:+.1f}%)")
