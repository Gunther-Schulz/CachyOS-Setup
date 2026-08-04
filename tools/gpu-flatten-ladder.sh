#!/usr/bin/env bash
# gpu-flatten-ladder.sh — walk the flatten ANCHOR VOLTAGE down until the card cannot
# hold the target clock, soaking each rung. Finds the quiet setting.
#
# THE AXIS IS VOLTAGE, NOT OFFSET. gpu-uv-ladder.sh climbs a global offset and asks
# "how much extra clock will it take?" — a performance question. This holds the CLOCK
# fixed at roughly stock and asks "how little voltage will it accept?" — the quiet
# question. Each rung is more aggressive because the same clock is demanded from less
# voltage, and power goes as V²·f so every step down is worth real watts.
#
# Measured stock on this card: 2803 MHz @ 1075 mV, 370 W. Modelled from its own curve,
# holding ~2800 MHz while walking the anchor down is worth roughly:
#     1000 mV -> 337 W (-9%)    950 -> 299 W (-19%)
#      900 mV -> 264 W (-29%)   875 -> 245 W (-34%)
# The wall is wherever the silicon stops delivering 2800 MHz at that voltage.
#
# ⚠️ RUN THE STOCK BASELINE FIRST — `./tools/gpu-soak.sh --screen 1`. A failure at some
# anchor only implicates that anchor if the machine passed the same soak without one.
#
# CRASH RESUMABILITY. A hang can take the machine down mid-rung, so the ladder writes
# "STARTED <mv>" and syncs BEFORE each attempt. After a reboot, --resume reads that file:
# an anchor marked STARTED with no FINISHED is the one that hung.
#
# Usage:
#   sudo ./tools/gpu-flatten-ladder.sh --screen 1
#   sudo ./tools/gpu-flatten-ladder.sh --screen 1 --mhz 2850 --anchors "1000 975 950"
#   sudo ./tools/gpu-flatten-ladder.sh --resume
#
# Default rungs start at 1000 mV — only +48 MHz at the anchor, inside proven territory —
# and walk to 875, which needs ~+1000 MHz there and is a genuine unknown.

set -uo pipefail
export LC_ALL=C

ANCHORS="1000 975 950 925 900 875"
TARGET_MHZ=2800
PASSES=10
SCREEN=0
WINDOWED=""
RESUME=0

usage() { sed -n '2,30p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --anchors) ANCHORS=$2; shift 2 ;;
    --mhz) TARGET_MHZ=$2; shift 2 ;;
    --passes) PASSES=$2; shift 2 ;;
    --screen) SCREEN=$2; shift 2 ;;
    --windowed) WINDOWED="--windowed"; shift ;;
    --resume) RESUME=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (applies curve edits); re-run with sudo" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
HERE="$(cd "$(dirname "$0")" && pwd)"
FLATTEN="$HERE/gpu-flatten.sh"; SOAK="$HERE/gpu-soak.sh"
[ -x "$FLATTEN" ] && [ -x "$SOAK" ] || { echo "gpu-flatten.sh / gpu-soak.sh not found beside this script" >&2; exit 1; }
NVCURVE="$home/.local/bin/nvcurve"
STATE="${home}/bench/flatten-ladder-state.tsv"
mkdir -p "$(dirname "$STATE")"
say() { echo "$*" | tee -a "${STATE%.tsv}.log"; sync; }

if [ "$RESUME" = 1 ]; then
  [ -f "$STATE" ] || { echo "no state file at $STATE" >&2; exit 1; }
  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1} $2=="FINISHED"{if($1==s) s=""} END{print s}' "$STATE")
  LASTGOOD=$(awk -F'\t' '$2=="FINISHED" && $3=="PASS"{g=$1} END{print g+0}' "$STATE")
  say ""; say "═══ RESUME ═══"
  [ -n "$HUNG" ] && say "❌ anchor ${HUNG} mV was STARTED but never finished — it hung the machine." \
                 || say "No incomplete rung — the last run ended cleanly."
  say "Lowest anchor that PASSED: ${LASTGOOD} mV"
  [ "$LASTGOOD" -gt 0 ] && say "RECOMMENDED: one rung ABOVE that (higher voltage), for margin."
  say ""; say "Full state: $STATE"; exit 0
fi

cleanup() { [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1; echo "curve reset to stock."; }
trap cleanup EXIT INT TERM

: > "$STATE"
say "=== flatten ladder — walking the anchor voltage DOWN ==="
say "target clock: ${TARGET_MHZ} MHz held at every rung (stock is ~2803 MHz)"
say "anchors:      $ANCHORS mV"
say "soak:         $PASSES passes each (~$(( PASSES * 167 / 60 )) min per rung)"
say "state:        $STATE   (survives a hang — resume with --resume)"
say ""
say "Each rung demands the SAME clock from LESS voltage. Power goes as V²·f, so every"
say "step down is worth real watts; the wall is where the silicon stops delivering."
say ""

LAST_GOOD=0
FAILED=""

for mv in $ANCHORS; do
  say "───────────────────────────────────────────────"
  say "ANCHOR ${mv} mV → ${TARGET_MHZ} MHz   ($(date +%H:%M:%S))"
  printf '%s\tSTARTED\t\t%s\n' "$mv" "$(date -Is)" >> "$STATE"; sync

  if ! "$FLATTEN" --mv "$mv" --mhz "$TARGET_MHZ" >/dev/null 2>&1; then
    say "  ⚠️ flatten could not be applied at ${mv} mV (delta out of range, or write failed)"
    printf '%s\tFINISHED\tSKIPPED\t%s\n' "$mv" "$(date -Is)" >> "$STATE"; sync
    continue
  fi

  "$SOAK" --passes "$PASSES" --screen "$SCREEN" $WINDOWED
  rc=$?
  case "$rc" in
    0) say "  ✓ ${mv} mV PASSED"
       printf '%s\tFINISHED\tPASS\t%s\n' "$mv" "$(date -Is)" >> "$STATE"; sync
       LAST_GOOD=$mv ;;
    2) say "  ⚠️ INCONCLUSIVE — the benchmark never ran. Fix that and restart."
       printf '%s\tFINISHED\tINCONCLUSIVE\t%s\n' "$mv" "$(date -Is)" >> "$STATE"; sync
       exit 2 ;;
    *) say "  ✗ ${mv} mV FAILED"
       printf '%s\tFINISHED\tFAIL\t%s\n' "$mv" "$(date -Is)" >> "$STATE"; sync
       FAILED=$mv; break ;;
  esac
  "$NVCURVE" write --reset >/dev/null 2>&1     # clean slate before the next rung
done

say ""
say "═══════════════════════════════════════════════"
[ -n "$FAILED" ] && say "First failure:  ${FAILED} mV" || say "No failure across the tested rungs."
say "Lowest good:    ${LAST_GOOD} mV"
if [ "$LAST_GOOD" -gt 0 ]; then
  PREV=$(echo "$ANCHORS" | tr ' ' '\n' | sort -n | awk -v g="$LAST_GOOD" '$1>g{print; exit}')
  say ""
  say "RECOMMENDED for daily use: ${PREV:-$LAST_GOOD} mV — one rung ABOVE the lowest that"
  say "  passed. The lowest passing anchor is the EDGE; margin is needed for a warm day,"
  say "  a driver update, and aging, and instability there is probabilistic."
  say ""
  say "Apply it:  sudo $FLATTEN --mv ${PREV:-$LAST_GOOD} --mhz $TARGET_MHZ"
  say "Then measure what it actually bought, against stock 2803 MHz / 370 W:"
  say "  sudo ./tools/gpu-soak.sh --screen $SCREEN --passes 10"
  say "and save it:  sudo $NVCURVE profile save quiet"
fi
say ""
say "Curve reset to stock. Nothing persists across a reboot."
