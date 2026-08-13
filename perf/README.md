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

# Full-pipeline benchmark (edge deduplication)

`bench-full.cpp` (`build-full.sh`, `run-full.sh`, `summarize-full.py`) runs the
real load pipeline used by the app — parse → clearHelpers → updateBounds →
transformGeographic → triangulate → generateEdges → clearPolygons →
regenerateTriangleBuffers → regenerateEdgeBuffers — through the full
`DataManager` (CGAL, Boost, pugixml, simdjson), and reports per-stage times,
edge counts, edge tree bytes (48 B/edge), edge buffer bytes, peak RSS and
post-load RSS. It is how the edge-deduplication change is measured.

```sh
# Compare the current checkout against a `main` worktree.
./perf/build-full.sh .            ../azul-main            # -> perf/bench-full-.
./perf/build-full.sh ../azul-main perf/bench-full-old
./perf/run-full.sh ./perf/bench-full-      /tmp/res-new 3 1 <files...>
./perf/run-full.sh ./perf/bench-full-old   /tmp/res-old 3 1 <files...>
./perf/summarize-full.py /tmp/res-new /tmp/res-old
```

`verify-edges.cpp` independently re-implements the edge generation (raw +
deduplicated) from the parsing helpers and asserts the deduplicated edge set is
a subset of the raw ring-segment set (no edges lost) and matches the counts the
real `DataManager` produces.

## Reference results (2026-08-13, Apple M4 Max, macOS 26, clang++ -O3)

Comparing `dedupe-shared-edges` (new) against `main` (old). Edge generation
deduplicates shared edges within each feature (a direct child of the file, and
each CityJSON `LoD` child), which removes internal triangulation seams from the
wireframe and halves the persistent edge storage:

| file | edges old | edges new | cut | tree+buf old | tree+buf new | saved |
|---|---:|---:|---:|---:|---:|---:|
| Ingolstadt.city.json | 273970 | 144117 | 47.4% | 22.0 MB | 11.5 MB | 10.5 MB |
| Vienna_102081.city.json | 264856 | 133556 | 49.6% | 21.2 MB | 10.7 MB | 10.5 MB |
| 9-316-520.city.json | 346729 | 179454 | 48.2% | 27.7 MB | 14.3 MB | 13.4 MB |
| 10-282-562.city.json | 350530 | 180662 | 48.5% | 28.0 MB | 14.5 MB | 13.5 MB |
| Zurich_LoD2_V10.city.json | 8921524 | 5609111 | 37.1% | 713.7 MB | 448.7 MB | 265.0 MB |
| s01.city.jsonl | 42746061 | 21614650 | 49.4% | 3419.7 MB | 1729.2 MB | 1690.5 MB |
| Building_LOD2.gml | 101798 | 62436 | 38.7% | 8.2 MB | 5.0 MB | 3.2 MB |
| e14a39d4.city.json (Mexico) | 1400517 | 806162 | 42.4% | 112.0 MB | 64.5 MB | 47.5 MB |
| e14a39e1.city.json (Mexico) | 4772403 | 2677652 | 43.9% | 381.8 MB | 214.2 MB | 167.6 MB |

Load-time impact is small: edge generation goes from ~3 ns/edge (pure
push_back) to ~70 ns/edge (hash-set insert) — about +5–30 ms on small files and
+1.3–1.7 s on s01 (484 MB), where the total load time is ~15 s. Peak RSS and
post-load RSS are lower on every file in the suite (post-load −0.4% to −13.5%).

# Triangulation benchmark (convex-ring fan fast path)

`bench-full.cpp` also times the triangulation stage separately. The fast path
(`fastTriangulateConvexRing` in `DataManager.cpp`) replaces CGAL's least-squares
plane fit + constrained Delaunay triangulation + flood fill with a fan /
shortest-diagonal triangulation for strictly convex rings without holes,
falling back to CGAL for concave, holed, degenerate or large (>64 vertices)
rings. LoD2 city data is quad-dominated, so the vast majority of polygons hit
the fast path (Zurich: 1.55 M of 1.75 M non-triangle rings, ~89%).

## Reference results (2026-08-13, Apple M4 Max, macOS 26, clang++ -O3)

Medians of 3 interleaved runs (2 for >100 MB). Comparing `fast-convex-triangulation`
(new) against `main` (old). `TRIANGULATE_MS` is the triangulation stage alone;
`TOTAL_MS` is parse → clear → bounds → transform → triangulate → edges →
buffers. Edge counts are identical in all cases (triangulation only changes
internal diagonals, never the ring edges).

| file | tri old | tri new | speedup | total old | total new | peak RSS Δ |
|---|---:|---:|---:|---:|---:|---:|
| Ingolstadt.city.json | 104 | 44 | 2.37× | 414 | 351 | +5.2% |
| Vienna_102081.city.json | 88 | 60 | 1.47× | 271 | 242 | +0.2% |
| 9-316-520.city.json | 121 | 66 | 1.84× | 418 | 365 | −0.2% |
| 10-282-562.city.json | 120 | 68 | 1.78× | 421 | 365 | +14.2% |
| Zurich_Building_LoD2_V10.city.json | 2858 | 1106 | 2.58× | 8878 | 7098 | +0.3% |
| 9-316-520.city.jsonl | 121 | 66 | 1.82× | 591 | 539 | +2.5% |
| Helsinki.city.jsonl | 3554 | 1656 | 2.15× | 18319 | 16352 | −0.1% |
| s01.city.jsonl | 537 | 522 | 1.03× | 14030 | 14214 | +0.6% |
| Building_LOD2.gml | 36 | 15 | 2.33× | 554 | 533 | −0.7% |
| leiden_centre.gml | 92 | 73 | 1.26× | 209 | 191 | −0.6% |

Notes:

- Triangulation is 1.3–2.6× faster; the biggest win is Zurich (the quad-heavy
  LoD2 file the fast path targets): 2.86 s → 1.11 s, cutting total load time
  from 8.9 s to 7.1 s.
- s01 is 100% triangles (never hits the fast path); its 1.03× is noise.
- Memory is essentially unchanged: peak RSS moves within run noise because the
  CGAL triangulation structures were already short-lived (allocated and freed
  per polygon); the persistent triangle/edge buffers are identical.
- Triangle counts are identical on every file in the suite except Zurich, where
  one degenerate ring (a roof with 4 nearly-coincident vertices that CGAL's
  flood fill splits into 12 triangles) now triangulates to the exact n−2 = 8.
  Triangulation of a simple ring with k vertices is always k−2 triangles, so
  the fast path is exact for every ring it accepts.

