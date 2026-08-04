#!/usr/bin/env bash
# gpu-clock-ladder.sh — ONE run that answers the whole question:
#   "At a voltage meaningfully below stock, how much clock can this card hold?"
#
# WHY THIS REPLACES THE EARLIER LADDERS. The setting is a PAIR — (anchor voltage,
# target clock) — and each earlier ladder walked one axis with the other frozen at a
# value chosen in advance. The flatten ladder froze the clock at ~stock, so it could
# only ever produce the quiet answer; the offset ladder had no voltage ceiling at all,
# so it was limited by the top of the curve (which is what hung at +400).
#
# Here the anchor is FIXED at a voltage already proven to hold, and the TARGET CLOCK is
# laddered upward. That is the axis that decides the outcome:
#   clock lands ABOVE stock -> more performance AND less power. Unambiguous win.
#   clock lands BELOW stock -> you see the exact trade and choose.
#
# THE BASELINE RUNS FIRST, IN THIS SAME SESSION. Every earlier comparison in this repo
# broke because the baseline was measured under different conditions — a manual run
# before a parser fix, a different RAM speed, a leaderboard of unknown platform. Ambient
# drifts and this card loses 2.5 MHz/degC, so a baseline from hours ago is not a control.
#
# MEASURED FACTS this is built on (2026-08-04, GravityMark RT 2560x1440 / 200k):
#   stock:            2803 MHz, 371 W, 1.075 V
#   flatten @1000 mV: 2677 MHz, 318 W, 1.000 V  <- voltage ceiling CONFIRMED holding
#   The ~120 MHz shortfall against the curve value is boost derating, seen at stock too
#   (2803 delivered where the curve says 2917), NOT a failure of the flatten.
#
# Usage:
#   sudo ./tools/gpu-clock-ladder.sh --screen 1
#   sudo ./tools/gpu-clock-ladder.sh --screen 1 --mv 950 --clocks "2800 2900 3000"
#   sudo ./tools/gpu-clock-ladder.sh --resume        # after a hang + reboot
#   ./tools/gpu-ladder-report.sh --state ~/bench/clock-ladder-state.tsv

set -uo pipefail
export LC_ALL=C

ANCHOR_MV=1000
CLOCKS="2800 2900 3000 3100"
PASSES=8
SCREEN=0
WINDOWED=""
RESUME=0
SKIP_BASE=0

usage() { sed -n '2,32p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mv) ANCHOR_MV=$2; shift 2 ;;
    --clocks) CLOCKS=$2; shift 2 ;;
    --passes) PASSES=$2; shift 2 ;;
    --screen) SCREEN=$2; shift 2 ;;
    --windowed) WINDOWED="--windowed"; shift ;;
    --resume) RESUME=1; shift ;;
    --skip-baseline) SKIP_BASE=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (applies curve edits); re-run with sudo" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
HERE="$(cd "$(dirname "$0")" && pwd)"
FLATTEN="$HERE/gpu-flatten.sh"; SOAK="$HERE/gpu-soak.sh"
[ -x "$FLATTEN" ] && [ -x "$SOAK" ] || { echo "gpu-flatten.sh / gpu-soak.sh missing" >&2; exit 1; }
NVCURVE="$home/.local/bin/nvcurve"
STATE="${home}/bench/clock-ladder-state.tsv"
mkdir -p "$(dirname "$STATE")"
say() { echo "$*" | tee -a "${STATE%.tsv}.log"; sync; }

if [ "$RESUME" = 1 ]; then
  [ -f "$STATE" ] || { echo "no state file at $STATE" >&2; exit 1; }
  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1} $2=="FINISHED"{if($1==s) s=""} END{print s}' "$STATE")
  LASTGOOD=$(awk -F'\t' '$2=="FINISHED" && $3=="PASS" && $1!="stock"{g=$1} END{print g+0}' "$STATE")
  say ""; say "═══ RESUME ═══"
  [ -n "$HUNG" ] && say "❌ target ${HUNG} MHz was STARTED but never finished — it hung the machine." \
                 || say "No incomplete rung — the last run ended cleanly."
  say "Highest target that PASSED: ${LASTGOOD} MHz"
  [ "$LASTGOOD" -gt 0 ] && say "RECOMMENDED: one rung BELOW that, for margin."
  say ""; say "Report:  ./tools/gpu-ladder-report.sh --state $STATE"; exit 0
fi

cleanup() { [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1; echo "curve reset to stock."; }
trap cleanup EXIT INT TERM

: > "$STATE"
NRUNGS=$(echo "$CLOCKS" | wc -w)
say "=== clock ladder at a fixed ${ANCHOR_MV} mV voltage ceiling ==="
say "anchor:   ${ANCHOR_MV} mV (held constant — the voltage ceiling)"
say "targets:  $CLOCKS MHz"
say "soak:     $PASSES passes each (~$(( PASSES * 167 / 60 )) min per rung)"
say "total:    ~$(( (NRUNGS + (1 - SKIP_BASE)) * PASSES * 167 / 60 )) min incl. baseline"
say "state:    $STATE   (survives a hang — resume with --resume)"
say ""
say "Baseline runs FIRST in this same session, so every rung is compared against a"
say "control measured minutes earlier rather than hours ago at a different ambient."
say ""

run_rung() {   # $1 = label for the state file
  local label=$1
  printf '%s\tSTARTED\t\t%s\n' "$label" "$(date -Is)" >> "$STATE"; sync
  "$SOAK" --passes "$PASSES" --screen "$SCREEN" $WINDOWED
  local rc=$?
  case "$rc" in
    0) say "  ✓ $label PASSED"; printf '%s\tFINISHED\tPASS\t%s\n' "$label" "$(date -Is)" >> "$STATE" ;;
    2) say "  ⚠️ INCONCLUSIVE — the benchmark never ran."; printf '%s\tFINISHED\tINCONCLUSIVE\t%s\n' "$label" "$(date -Is)" >> "$STATE" ;;
    *) say "  ✗ $label FAILED"; printf '%s\tFINISHED\tFAIL\t%s\n' "$label" "$(date -Is)" >> "$STATE" ;;
  esac
  sync
  return $rc
}

# ── 0. baseline, at stock ────────────────────────────────────────────────────────────
if [ "$SKIP_BASE" = 0 ]; then
  say "───────────────────────────────────────────────"
  say "BASELINE — stock curve   ($(date +%H:%M:%S))"
  "$NVCURVE" write --reset >/dev/null 2>&1
  run_rung "stock" || { say "baseline FAILED — the card is unstable at stock. Stop and investigate."; exit 1; }
  say ""
fi

# ── 1..N. fixed anchor, rising target clock ──────────────────────────────────────────
LAST_GOOD=0; FAILED=""
for mhz in $CLOCKS; do
  say "───────────────────────────────────────────────"
  say "TARGET ${mhz} MHz @ ${ANCHOR_MV} mV   ($(date +%H:%M:%S))"
  if ! "$FLATTEN" --mv "$ANCHOR_MV" --mhz "$mhz" >/dev/null 2>&1; then
    say "  ⚠️ flatten refused (delta out of nvcurve's ±1000 MHz range?) — skipping"
    printf '%s\tFINISHED\tSKIPPED\t%s\n' "$mhz" "$(date -Is)" >> "$STATE"; sync
    continue
  fi
  if run_rung "$mhz"; then LAST_GOOD=$mhz; else FAILED=$mhz; break; fi
  "$NVCURVE" write --reset >/dev/null 2>&1
done

say ""
say "═══════════════════════════════════════════════"
[ -n "$FAILED" ] && say "First failure:  ${FAILED} MHz" || say "No failure across the tested targets."
say "Highest good:   ${LAST_GOOD} MHz @ ${ANCHOR_MV} mV"
if [ "$LAST_GOOD" -gt 0 ]; then
  PREV=$(echo "$CLOCKS" | tr ' ' '\n' | sort -n | awk -v g="$LAST_GOOD" '$1<g{p=$1} END{print p+0}')
  say ""
  say "RECOMMENDED: ${PREV:-$LAST_GOOD} MHz — one rung BELOW the highest that passed."
  say "  Instability at the edge is probabilistic; a rung that passed today can fail on a"
  say "  longer sample. Margin covers a warm day, a driver update, and aging."
  say ""
  say "Apply:   sudo $FLATTEN --mv $ANCHOR_MV --mhz ${PREV:-$LAST_GOOD}"
  say "Save:    sudo $NVCURVE profile save quiet"
fi
say ""
say "FULL TABLE — every rung against the baseline measured in this same session:"
say "  ./tools/gpu-ladder-report.sh --state $STATE"
say ""
say "Curve reset to stock. Nothing persists across a reboot."
