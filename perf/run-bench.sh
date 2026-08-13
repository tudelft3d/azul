#!/bin/zsh
# Run the parsing benchmark over a set of files.
#
# Usage: ./run-bench.sh <binary> <out-dir> <runs-small> <runs-large> <files...>
#
#   <binary>      bench binary (see build.sh)
#   <out-dir>     directory for per-run raw output files
#   <runs-small>  repeats for files <= 100MB
#   <runs-large>  repeats for files > 100MB
#   <files...>    the .json / .city.json / .jsonl files to parse
#
# Prints one tab-separated line per run to stdout:
#   <file>  <run>  <parse_ms>  <peak_rss_mb>
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
    ms=$(grep '^PARSE_MS ' "$out" | awk '{print $2}')
    rss=$(grep '^PEAK_RSS_MB ' "$out" | awk '{print $2}')
    echo -e "${base}\t${i}\t${ms}\t${rss}"
  done
done
