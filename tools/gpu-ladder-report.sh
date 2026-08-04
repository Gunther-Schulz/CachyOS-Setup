#!/usr/bin/env bash
# gpu-ladder-report.sh — join a ladder's state file with its per-rung soak data and
# print ONE comparison table: power, clock, temperature, fan and score per rung.
#
# WHY THIS IS SEPARATE. The ladders record only PASS/FAIL; each rung's measurements live
# in its own ~/bench/soak-*/ directory, written by gpu-soak.sh. Without joining them you
# are scrolling terminal history to compare rungs — and the whole point of walking the
# anchor down is to SEE where the returns flatten, which is a table question.
#
# It reads only completed files, so it is safe to run WHILE a ladder is in progress —
# useful for deciding to stop early once the gains die, which is a better stopping rule
# than running until something hangs.
#
# Rungs are matched to soak directories by TIMESTAMP: each STARTED line in the state file
# is paired with the first soak directory created at or after it.
#
# Usage:
#   ./tools/gpu-ladder-report.sh                    # flatten ladder (default)
#   ./tools/gpu-ladder-report.sh --offset           # the global-offset ladder instead
#   ./tools/gpu-ladder-report.sh --state <path>

set -uo pipefail
export LC_ALL=C

home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
STATE="$home/bench/flatten-ladder-state.tsv"
UNIT="mV"

while [ $# -gt 0 ]; do
  case "$1" in
    --offset) STATE="$home/bench/uv-ladder-state.tsv"; UNIT="MHz"; shift ;;
    --state) STATE=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -f "$STATE" ] || { echo "no state file at $STATE" >&2; exit 1; }

# stock reference, measured 2026-08-04 (GravityMark RT, 2560x1440, 200k asteroids)
REF_W=370; REF_MHZ=2803; SESSION_REF=""

printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' \
  "rung" "verdict" "mean W" "vs stock" "mean MHz" "peak C" "peak fan" "mean score" "passes"
printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' \
  "--------" "--------" "---------" "---------" "--------" "-------" "---------" "----------" "------"

# Parse with awk, NOT `IFS=$'\t' read`: tab is an IFS *whitespace* character, so bash
# COLLAPSES consecutive tabs and the empty verdict field silently disappears — shifting
# the timestamp into the wrong variable and breaking every join.
while IFS='|' read -r rung ts; do
  [ -n "$rung" ] || continue
  # first soak dir created at or after this rung started
  d=$(for x in "$home"/bench/soak-*/; do
        [ -f "$x/sensors.txt" ] || continue
        xs=$(date -r "$x" +%s 2>/dev/null) || continue
        rs=$(date -d "$ts" +%s 2>/dev/null) || continue
        [ "$xs" -ge $((rs - 5)) ] && echo "$xs $x"
      done | sort -n | head -1 | cut -d' ' -f2-)
  # verdict comes from the matching FINISHED line, if it exists yet
  v=$(awk -F'\t' -v r="$rung" '$1==r && $2=="FINISHED"{print $3}' "$STATE" | tail -1)
  v=${v:-RUNNING}
  if [ -z "$d" ] || [ ! -s "$d/sensors.txt" ]; then
    printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' "$rung" "$v" "-" "-" "-" "-" "-" "-" "-"
    continue
  fi
  read -r mw mf pt pfan < <(awk '$3!="n/a" && $3+0>100 {n++; w+=$3; f+=$2; if($4+0>t)t=$4+0; if($5+0>fa)fa=$5+0}
       END{if(n) printf "%.0f %.0f %.0f %.0f", w/n, f/n, t, fa; else printf "- - - -"}' "$d/sensors.txt")
  ms="-"; np=0
  if [ -s "$d/scores.txt" ]; then
    np=$(grep -c . "$d/scores.txt")
    ms=$(awk '{s+=$1;n++} END{if(n) printf "%.0f", s/n; else print "-"}' "$d/scores.txt")
  fi
  # If this ladder measured its own stock baseline, compare against THAT rather than the
  # hardcoded reference — a control from the same session beats one from hours earlier.
  if [ "$rung" = "stock" ] && [ "$mw" != "-" ]; then REF_W=$mw; REF_MHZ=$mf; SESSION_REF=1; fi
  dw="-"; [ "$mw" != "-" ] && dw=$(awk -v a="$mw" -v b="$REF_W" 'BEGIN{printf "%+.0f%%", (a/b-1)*100}')
  printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' \
    "$rung" "$v" "$mw" "$dw" "$mf" "$pt" "$pfan" "$ms" "$np"
done < <(awk -F'\t' '$2=="STARTED"{print $1"|"$4}' "$STATE")

cat <<EOF

stock reference: ${REF_MHZ} MHz, ${REF_W} W${SESSION_REF:+  <- measured in THIS ladder run (proper control)}

HOW TO READ IT. Walk DOWN the rungs and watch the "vs stock" column. Stop where the
gains flatten — two more rungs for another 1% is not worth the reduced margin, and that
is a better stopping rule than running until something hangs. The wall still tells you
how much headroom you are sitting on, but it should not decide where you live.

Watch "mean score" too: a rung that saves power while the score falls is not a win, it
is a power cap in disguise. The goal is stock performance at less power.
EOF
