# Parsing performance benchmark

Compares the JSON/JSONL parsing helpers (`src/DataManager/JSONParsingHelper.hpp`,
`JSONLinesParsingHelper.hpp`) between two checkouts. Only the parsing helpers
and simdjson are compiled — no CGAL, Boost, or AppKit — so the measurements are
a pure reflection of parsing speed and peak RSS. Build with optimisation.

## Usage

```sh
# 1. Check out both versions. Use the current checkout for the new code and a
#    git worktree of `main` for the old code.
git worktree add --detach ../azul-main main

# 2. Build both benchmark binaries (-O3).
./perf/build.sh .                                  # -> perf/bench-azul
./perf/build.sh ../azul-main                       # -> perf/bench-azul-main

# 3. Run both over the same files. 3 repeats for <=100MB, 2 for larger.
#    Redirect stdout to a log so the parser's status output stays out of the way.
./perf/run-bench.sh ./perf/bench-azul      /tmp/res-new 3 2 \
    data/9-316-520.city.json data/Zurich_Building_LoD2_V10.city.json \
    data/9-316-520.city.jsonl data/Helsinki.city.jsonl > /tmp/new.tsv 2>&1
./perf/run-bench.sh ./perf/bench-azul-main /tmp/res-old 3 2 \
    data/9-316-520.city.json data/Zurich_Building_LoD2_V10.city.json \
    data/9-316-520.city.jsonl data/Helsinki.city.jsonl > /tmp/old.tsv 2>&1

# 4. Summarise (second dir = baseline; speedup = old/new).
./perf/summarize.py /tmp/res-new /tmp/res-old
```

`run-bench.sh` writes one file per run into the result dir; each contains
`PARSE_MS`, `PEAK_RSS_MB` (from `getrusage`, the process peak) and object
counts (`CHILDREN`, `POLYGONS`, `RING_POINTS`, `STYLES`, `THEMES`,
`ATTRIBUTES`) for verifying that both parsers produce identical output.

`bench.cpp` picks the parser by extension: `.city.json`/`.cityjson` and
`.json` → `JSONParsingHelper`, `.jsonl` → `JSONLinesParsingHelper`.

## Reference results (2026-08-13, Apple M4 Max, macOS 26, clang++ -O3)

Comparing `perf/cityjson-streamed-dom-parse` (new: simdjson DOM) against
`main` (old: simdjson ondemand + `std::any`). Parse output is byte-identical
between branches on all files below.

| file | size | new | old | speedup | new RSS | old RSS | RSS Δ |
|---|---|---:|---:|---:|---:|---:|---:|
| Ingolstadt.city.json | 4.8M | 235ms | 382ms | 1.63× | 130MB | 120MB | +8.2% |
| Vienna_102081.city.json | 5.4M | 117ms | 280ms | 2.38× | 84MB | 75MB | +12.9% |
| 9-316-520.city.json | 8.1M | 210ms | 449ms | 2.13× | 146MB | 131MB | +11.2% |
| 10-282-562.city.json | 8.9M | 211ms | 440ms | 2.09× | 153MB | 136MB | +12.5% |
| e14a39d4.city.json (Mexico tile) | 20M | 102ms | 892ms | 8.79× | 233MB | 270MB | −13.8% |
| e14a39e1.city.json (Mexico tile) | 62M | 325ms | 2445ms | 7.51× | 732MB | 889MB | −17.7% |
| Zurich_LoD2_V10.city.json | 279M | 3.78s | 8.93s | 2.36× | 4174MB | 3599MB | +16.0% |
| 9-316-520.city.jsonl | 7.4M | 377ms | 487ms | 1.29× | 125MB | 126MB | −1.2% |
| Helsinki.city.jsonl | 412M | 12.3s | 15.5s | 1.27× | 4745MB | 4765MB | −0.4% |
| s01.city.jsonl | 461M | 7.1s | 12.0s | 1.69× | 4377MB | 4396MB | −0.4% |

Notes:

- Speed is consistently better; the win grows with object count (Mexico tiles:
  ~46k objects each → 7.5–8.8×; sparse `data/` files → ~2×).
- Memory: JSONL streaming (`parse_many`) is slightly lighter than ondemand
  streaming; Mexico tiles are −14 to −18%. Single-document CityJSON DOM is
  +8–16% vs ondemand (DOM holds the full tape while ondemand reads lazily).
- Peak RSS here is the whole process, parse-only; in the app the delta is on
  top of GUI/Metal buffers.
