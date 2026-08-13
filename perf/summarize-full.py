#!/usr/bin/env python3
# Summarise full-pipeline benchmark results comparing two result dirs
# (first = new/dedupe code, second = old/baseline). Also accepts the TSV lines
# produced by run-full.sh on stdin as an alternative to result dirs.
import collections
import os
import re
import sys

def load_from_dir(d):
    per_file = collections.defaultdict(list)
    for name in os.listdir(d):
        m = re.match(r"^(.*)\.(\d+)\.txt$", name)
        if not m:
            continue
        vals = {}
        with open(os.path.join(d, name)) as fh:
            for line in fh:
                parts = line.split()
                if len(parts) == 2 and parts[0] in (
                    "PARSE_MS", "TRIANGULATE_MS", "EDGE_GEN_MS", "BUFFERS_MS",
                    "TOTAL_MS", "PEAK_RSS_MB", "POST_RSS_MB", "EDGES",
                    "EDGE_TREE_BYTES", "EDGE_BUFFER_BYTES"):
                    vals[parts[0]] = float(parts[1])
        if vals:
            per_file[m.group(1)].append(vals)
    return {f: means(r) for f, r in per_file.items()}

def means(runs):
    keys = runs[0].keys()
    out = {}
    for k in keys:
        out[k] = sum(r[k] for r in runs) / len(runs)
    return out

def order(files):
    order = ["Ingolstadt.city.json", "Vienna_102081.city.json",
             "9-316-520.city.json", "10-282-562.city.json",
             "Zurich_Building_LoD2_V10.city.json",
             "9-316-520.city.jsonl", "Helsinki.city.jsonl", "s01.city.jsonl"]
    known = [f for f in order if f in files]
    return known + [f for f in sorted(files) if f not in order]

if len(sys.argv) != 3:
    print("usage: summarize-full.py <new-result-dir> <old-result-dir>")
    sys.exit(1)

new = load_from_dir(sys.argv[1])
old = load_from_dir(sys.argv[2])

print(f"{'file':<34}{'edge ms':>8}{'old ms':>8}{'total ms':>10}{'old tot':>10}{'edges':>11}{'old ed':>11}{'edge cut':>8} | {'tree MB':>8}{'old MB':>8}{'buf MB':>7}{'old MB':>7} | {'post RSS':>9}{'old RSS':>9}{'rss Δ':>8}")
for f in order(new):
    if f not in old:
        continue
    n, o = new[f], old[f]
    edgeCut = (1 - n["EDGES"] / o["EDGES"]) * 100 if o["EDGES"] else 0
    treeMB = n["EDGE_TREE_BYTES"] / 1e6; otreeMB = o["EDGE_TREE_BYTES"] / 1e6
    bufMB = n["EDGE_BUFFER_BYTES"] / 1e6; obufMB = o["EDGE_BUFFER_BYTES"] / 1e6
    rssDelta = (n["POST_RSS_MB"] / o["POST_RSS_MB"] - 1) * 100 if o["POST_RSS_MB"] else 0
    print(f"{f:<34}{n['EDGE_GEN_MS']:>8.0f}{o['EDGE_GEN_MS']:>8.0f}"
          f"{n['TOTAL_MS']:>10.0f}{o['TOTAL_MS']:>10.0f}"
          f"{n['EDGES']:>11.0f}{o['EDGES']:>11.0f}{edgeCut:>7.1f}%"
          f" | {treeMB:>8.1f}{otreeMB:>8.1f}{bufMB:>7.1f}{obufMB:>7.1f}"
          f" | {n['POST_RSS_MB']:>9.0f}{o['POST_RSS_MB']:>9.0f}{rssDelta:>+7.1f}%")
