#!/usr/bin/env bash
# gpu-uv-ladder.sh — climb V/F offsets, soaking each one, until something breaks.
#
# Wraps gpu-soak.sh: for each offset it applies the setting, runs a full soak at gaming
# clocks, and stops at the first failure — then reports the last-good offset and the
# recommendation one step BELOW it.
#
# WHY A WRAPPER AND NOT ONE BIG SCRIPT: gpu-soak.sh already owns the hard parts (running
# at gaming clocks, two independent hang detectors, distinguishing a launch failure from
# instability). This only sequences it. A bug fixed in the soak is fixed here too.
#
# ⚠️ RUN THE STOCK BASELINE FIRST — `./tools/gpu-soak.sh --screen 1`. A failure at some
# offset only implicates that offset if the machine passed the SAME soak without one.
#
# CRASH RESUMABILITY. A hang at the wall can take the whole machine down, so the ladder
# writes "STARTED +N" to its state file and syncs BEFORE each attempt. After a reboot,
# `--resume` reads that file: any offset marked STARTED but not FINISHED is the one that
# hung, and the ladder reports it as the failure rather than re-running it.
#
# Usage:
#   sudo ./tools/gpu-uv-ladder.sh --screen 1
#   sudo ./tools/gpu-uv-ladder.sh --screen 1 --offsets "250 300 350 400"
#   sudo ./tools/gpu-uv-ladder.sh --screen 1 --passes 16     # longer soak per rung
#   sudo ./tools/gpu-uv-ladder.sh --resume                   # after a hang + reboot
#
# Default rungs start at +250 because it already produced a clean GravityMark run
# (81 399, +3.2%), and stop at +400 because that one hung with Xid 109 on 2026-08-04.
# The wall is known to be between them; this finds where.

set -uo pipefail
export LC_ALL=C

OFFSETS="250 300 350 400"
PASSES=10                 # ~28 min per rung. Bracket with these, then soak the winner long.
SCREEN=0
WINDOWED=""
RESUME=0
STATE="${HOME}/bench/uv-ladder-state.tsv"

usage() { sed -n '2,30p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --offsets) OFFSETS=$2; shift 2 ;;
    --passes) PASSES=$2; shift 2 ;;
    --screen) SCREEN=$2; shift 2 ;;
    --windowed) WINDOWED="--windowed"; shift ;;
    --resume) RESUME=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (applies V/F offsets); re-run with sudo" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
STATE="${home}/bench/uv-ladder-state.tsv"
SOAK="$(cd "$(dirname "$0")" && pwd)/gpu-soak.sh"
[ -x "$SOAK" ] || { echo "gpu-soak.sh not found beside this script" >&2; exit 1; }
NVCURVE="$home/.local/bin/nvcurve"

mkdir -p "$(dirname "$STATE")"
say() { echo "$*" | tee -a "${STATE%.tsv}.log"; sync; }

# --- resume: an offset STARTED but never FINISHED is the one that took the machine down
if [ "$RESUME" = 1 ]; then
  [ -f "$STATE" ] || { echo "no state file at $STATE — nothing to resume" >&2; exit 1; }
  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1} $2=="FINISHED"{if($1==s) s=""} END{print s}' "$STATE")
  LASTGOOD=$(awk -F'\t' '$2=="FINISHED" && $3=="PASS"{g=$1} END{print g+0}' "$STATE")
  say ""
  say "═══ RESUME ═══"
  if [ -n "$HUNG" ]; then
    say "❌ +${HUNG} MHz was STARTED but never finished — it hung the machine."
    say "   That is the failure. The wall is at or below +${HUNG}."
  else
    say "No incomplete rung found — the last run ended cleanly."
  fi
  say "Last offset that PASSED a full soak: +${LASTGOOD} MHz"
  [ "$LASTGOOD" -gt 0 ] && say "RECOMMENDED: one rung BELOW that, for margin."
  say ""
  say "Full state: $STATE"
  exit 0
fi

cleanup() {
  [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1
  echo "offsets reset to stock."
}
trap cleanup EXIT INT TERM

: > "$STATE"
say "=== V/F offset ladder ==="
say "rungs:   $OFFSETS"
say "soak:    $PASSES passes each (~$(( PASSES * 167 / 60 )) min per rung)"
say "screen:  $SCREEN"
say "state:   $STATE   (survives a hang — resume with --resume)"
say ""
say "Each rung is a full gpu-soak.sh run: gaming clocks, Xid + device-lost detection."
say "Stops at the first failure and reports the rung BELOW the last good one."
say ""

LAST_GOOD=0
FAILED=""

for off in $OFFSETS; do
  say "───────────────────────────────────────────────"
  say "RUNG +${off} MHz   ($(date +%H:%M:%S))"
  # Written and synced BEFORE the attempt: if the machine dies here, this line is the
  # evidence of which rung killed it.
  printf '%s\tSTARTED\t\t%s\n' "$off" "$(date -Is)" >> "$STATE"; sync

  "$SOAK" --offset "$off" --passes "$PASSES" --screen "$SCREEN" $WINDOWED
  rc=$?

  case "$rc" in
    0) say "  ✓ +${off} PASSED a ${PASSES}-pass soak"
       printf '%s\tFINISHED\tPASS\t%s\n' "$off" "$(date -Is)" >> "$STATE"; sync
       LAST_GOOD=$off ;;
    2) say "  ⚠️ INCONCLUSIVE — the benchmark never ran. Fix that and restart the ladder."
       printf '%s\tFINISHED\tINCONCLUSIVE\t%s\n' "$off" "$(date -Is)" >> "$STATE"; sync
       exit 2 ;;
    *) say "  ✗ +${off} FAILED"
       printf '%s\tFINISHED\tFAIL\t%s\n' "$off" "$(date -Is)" >> "$STATE"; sync
       FAILED=$off; break ;;
  esac
done

say ""
say "═══════════════════════════════════════════════"
[ -n "$FAILED" ] && say "First failure:  +${FAILED} MHz" || say "No failure across the tested rungs — the wall is above +${OFFSETS##* }."
say "Last good:      +${LAST_GOOD} MHz"
if [ "$LAST_GOOD" -gt 0 ]; then
  PREV=$(echo "$OFFSETS" | tr ' ' '\n' | awk -v g="$LAST_GOOD" '$1<g{p=$1} END{print p+0}')
  say ""
  say "RECOMMENDED for daily use: +${PREV:-0} MHz — one rung below the last that passed."
  say "  The last passing setting is the EDGE. Margin is needed for a warm day, a driver"
  say "  update, and silicon aging, and instability at the edge is probabilistic — a rung"
  say "  that passed today can fail next month on a longer sample."
fi
say ""
say "Before trusting the chosen setting: soak it LONG (--passes 40) and play a real game."
say "One fixed scene cannot vary shaders and load the way a game does."
say ""
say "Apply:  sudo $NVCURVE write --global --delta <n>"
say "Undo:   sudo $NVCURVE write --reset   (or reboot — nothing persists)"
