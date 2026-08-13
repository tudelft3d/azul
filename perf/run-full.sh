#!/bin/zsh
# Run the full-pipeline benchmark over a set of files.
#
# Usage: ./run-full.sh <binary> <out-dir> <runs-small> <runs-large> <files...>
#
# Prints one tab-separated line per run to stdout:
#   <file> <run> <parse_ms> <triangulate_ms> <edge_ms> <buffers_ms> <total_ms>
#           <peak_rss_mb> <post_rss_mb> <edges> <edge_tree_bytes> <edge_buffer_bytes>
set -e
BIN="$1"; OUT="$2"; RUNS_SMALL="$3"; RUNS_LARGE="$4"
if [ -z "$BIN" ] || [ -z "$OUT" ] || [ -z "$RUNS_SMALL" ] || [ -z "$RUNS_LARGE" ] || [ $# -lt 5 ]; then
  echo "usage: $0 <binary> <out-dir> <runs-small> <runs-large> <files...>" >&2
  exit 1
fi
shift 4
mkdir -p "$OUT"

for f in "$@"; do
  base=$(basename "$f")
  size=$(du -m "$f" | cut -f1)
  if [ "$size" -gt 100 ]; then runs=$RUNS_LARGE; else runs=$RUNS_SMALL; fi
  echo "== $base (${size}MB, ${runs} runs) =="
  for i in $(seq 1 "$runs"); do
    out="$OUT/${base}.${i}.txt"
    "$BIN" "$f" > "$out" 2>&1 || true
    get() { grep "^$1 " "$out" | awk '{print $2}'; }
    parse=$(get PARSE_MS); tri=$(get TRIANGULATE_MS); edge=$(get EDGE_GEN_MS)
    buf=$(get BUFFERS_MS); total=$(get TOTAL_MS)
    peak=$(get PEAK_RSS_MB); post=$(get POST_RSS_MB)
    edges=$(get EDGES); tree=$(get EDGE_TREE_BYTES); ebuf=$(get EDGE_BUFFER_BYTES)
    echo -e "${base}\t${i}\t${parse}\t${tri}\t${edge}\t${buf}\t${total}\t${peak}\t${post}\t${edges}\t${tree}\t${ebuf}"
  done
done
