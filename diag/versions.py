#!/usr/bin/env python3
# versions.py RAW: per fasthttp version the median of both benchmarks over all layouts, their layout spread and the step to the previous version
import statistics
import sys
from collections import defaultdict

samples = defaultdict(list)
for line in open(sys.argv[1]):
    rnd, name, bench, ns = line.split()
    version, layout = name.rsplit("-", 1)
    samples[version, bench.split("/")[1], layout].append(float(ns))
benches = sorted({b for _, b, _ in samples})
versions = sorted({v for v, _, _ in samples}, key=lambda v: [int(p) for p in v.split(".")])
head = "".join(f"{b:>26}" for b in benches)
print(f"{'fasthttp':<9}{head}")
print(f"{'':<9}" + "".join(f"{'median   spread     step':>26}" for _ in benches))
previous = {}
for version in versions:
    row = f"{version:<9}"
    for bench in benches:
        layouts = [statistics.median(v) for (ver, b, _), v in samples.items() if ver == version and b == bench]
        if not layouts:
            row += f"{'no data':>26}"
            continue
        median = statistics.median(layouts)
        spread = max(layouts) - min(layouts)
        step = median - previous.get(bench, median)
        previous[bench] = median
        row += f"{median:14.1f} {spread:6.1f} {step:+7.1f}"
    print(row)
