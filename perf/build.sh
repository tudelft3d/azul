#!/bin/zsh
# Build the parsing benchmark against a given source tree.
#
# Usage: ./build.sh <src-dir> [output-binary]
#
#   <src-dir>  path to an azul checkout; the parsing helpers are read from
#              <src-dir>/src/DataManager/. Use the current checkout for the
#              new code and a `git worktree` of `main` for the old code.
#   [output]   output binary path (default: ./bench-<branch-name>)
#
# Compiles with -O3 -DNDEBUG. Only the parsing helpers + simdjson are built
# (no CGAL/Boost/AppKit), so the binary is a pure measure of parsing.
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
  OUT="$DIR/bench-$(basename "$SRC")"
fi

clang++ -std=c++17 -O3 -DNDEBUG \
  -I"$SRC/src/DataManager" \
  "$DIR/bench.cpp" "$SRC/src/DataManager/simdjson.cpp" \
  -o "$OUT"
echo "built $OUT"
