#!/usr/bin/env python3
# Summarise the per-run raw outputs produced by run-bench.sh.
#
# Usage: ./summarize.sh <result-dir> [<result-dir> ...]
#
# With one result dir: prints mean parse time (ms) and peak RSS (MB) per file.
# With two result dirs: additionally prints the speedup and RSS delta between
# the first (e.g. new code) and second (e.g. old code).
import collections
import os
import re
import sys

def load(d):
    per_file = collections.defaultdict(list)
    for name in os.listdir(d):
        m = re.match(r"^(.*)\.(\d+)\.txt$", name)
        if not m:
            continue
        path = os.path.join(d, name)
        ms = rss = None
        with open(path) as fh:
            for line in fh:
                if line.startswith("PARSE_MS "):
                    ms = float(line.split()[1])
                elif line.startswith("PEAK_RSS_MB "):
                    rss = float(line.split()[1])
        if ms is not None and rss is not None:
            per_file[m.group(1)].append((ms, rss))
    out = {}
    for f, runs in per_file.items():
        n = len(runs)
        out[f] = (sum(r[0] for r in runs) / n, sum(r[1] for r in runs) / n)
    return out

def order(files):
    order = ["Ingolstadt.city.json", "Vienna_102081.city.json",
             "9-316-520.city.json", "10-282-562.city.json",
             "Zurich_Building_LoD2_V10.city.json",
             "9-316-520.city.jsonl", "Helsinki.city.jsonl", "s01.city.jsonl"]
    known = [f for f in order if f in files]
    return known + [f for f in sorted(files) if f not in order]

dirs = [os.path.abspath(d) for d in sys.argv[1:]]
if not dirs:
    print("usage: summarize.py <result-dir> [<result-dir> ...]")
    sys.exit(1)

data = [load(d) for d in dirs]
names = [os.path.basename(d) for d in dirs]

if len(dirs) == 1:
    print(f"{'file':<32}{'parse ms':>10}{'peak rss':>10}")
    for f in order(data[0]):
        ms, rss = data[0][f]
        print(f"{f:<32}{ms:>10.0f}{rss:>10.0f}")
else:
    new, old = data[0], data[1]
    print(f"{'file':<32}{'new ms':>9}{'old ms':>9}{'speedup':>8}{'new rss':>9}{'old rss':>9}{'rss Δ':>8}")
    for f in order(new):
        if f not in old:
            continue
        nms, nrss = new[f]
        oms, orss = old[f]
        print(f"{f:<32}{nms:>9.0f}{oms:>9.0f}{oms/nms:>7.2f}x{nrss:>9.0f}{orss:>9.0f}{(nrss/orss-1)*100:>+7.1f}%")
