#!/usr/bin/env python3
# compare2.py RAW NAME...: median per variant and benchmark over all layouts, against the first name
import statistics
import sys
from collections import defaultdict

raw, names = sys.argv[1], sys.argv[2:]
values = defaultdict(list)
for line in open(raw):
    rnd, name, bench, ns = line.split()
    values[name.rsplit("-", 1)[0], bench.split("/")[1]].append(float(ns))
base = names[0]
print(f"{'benchmark':<16}" + "".join(f"{n:>22}" for n in names))
for bench in sorted({b for _, b in values}):
    row = f"{bench:<16}"
    reference = statistics.median(values[base, bench])
    for name in names:
        if (name, bench) not in values:
            row += f"{'no data':>22}"
            continue
        median = statistics.median(values[name, bench])
        row += f"{median:10.1f} {median - reference:+6.1f} ns" if name != base else f"{median:22.1f}"
    print(row)
