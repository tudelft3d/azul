#!/bin/zsh
# Build the full-pipeline benchmark against a given source tree.
#
# Usage: ./build-full.sh <src-dir> [output-binary]
#
# Compiles bench-full.cpp + the real DataManager (CGAL triangulation, edge
# generation, buffer regeneration) at -O3. Links the prebuilt static libs in
# <src-dir>/libs and the vendored headers in <src-dir>/include. Headers must be
# present locally (they are gitignored); Xcode Cloud fetches them via Homebrew.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$1"
if [ -z "$SRC" ]; then
  echo "usage: $0 <src-dir> [output]" >&2
  exit 1
fi

if [ -n "$2" ]; then
  OUT="$2"
else
  OUT="$DIR/bench-full-$(basename "$SRC")"
fi

if [ ! -d "$SRC/include/CGAL" ] || [ ! -d "$SRC/include/boost" ]; then
  echo "error: $SRC/include is missing vendored headers (boost/CGAL/gmp/mpfr)" >&2
  exit 1
fi

clang++ -std=c++17 -O3 -DNDEBUG \
  -I"$SRC/src/DataManager" -I"$SRC/include" \
  "$DIR/bench-full.cpp" \
  "$SRC/src/DataManager/DataManager.cpp" \
  "$SRC/src/DataManager/simdjson.cpp" \
  "$SRC/include/pugixml.cpp" \
  "$SRC/libs/libboost_thread.a" "$SRC/libs/libgmp.a" "$SRC/libs/libmpfr.a" "$SRC/libs/libpugixml.a" \
  -o "$OUT"
echo "built $OUT"
