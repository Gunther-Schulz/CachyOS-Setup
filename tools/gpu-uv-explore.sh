#!/usr/bin/env bash
# gpu-uv-explore.sh — unattended overnight sweep of BOTH axes, with the analysis built in.
#
# THE SETTING IS A PAIR: (anchor voltage, target clock). Every earlier tool here walked
# one axis with the other frozen at a guessed value, which is why none of them could
# answer the question on its own. This walks both and reports the frontier.
#
# IT IS NOT A GRID. Lower voltage can never hold MORE clock, so once the maximum at one
# anchor is known, the next (lower) anchor starts THERE and walks DOWN until it passes —
# typically one or two rungs instead of five. A naive grid would be ~20 rungs and 7 h;
# this is usually 8-10 rungs and 3-4 h.
#
# ALGORITHM
#   0. baseline at stock, in this same session (every broken comparison in this repo
#      came from a control measured under different conditions)
#   1. at the first anchor, climb the clock until a rung FAILS -> that anchor's maximum
#   2. at each lower anchor, start from the previous maximum and walk DOWN to the first
#      rung that PASSES -> that anchor's maximum
#   3. stop early if an anchor cannot hold even --floor MHz (that voltage is too low)
#   4. print the frontier and pick the winner, applying the back-off-one-rung rule
#
# WHAT CANNOT BE AUTOMATED: recovery from a HARD hang. If a rung locks the machine, the
# run ends there. The state file is synced before every attempt, so `--resume` reports
# which pair did it — but the remaining rungs need a re-run. Anchors are therefore
# ordered most-informative-first, so an overnight hang still leaves useful data.
#
# Usage:
#   sudo ./tools/gpu-uv-explore.sh --screen 1
#   sudo ./tools/gpu-uv-explore.sh --screen 1 --anchors "1000 950 900" --passes 6
#   sudo ./tools/gpu-uv-explore.sh --resume
#   ./tools/gpu-ladder-report.sh --state ~/bench/explore-state.tsv

set -uo pipefail
export LC_ALL=C

ANCHORS="1000 950 900 875"
CLOCKS="2800 2900 3000 3100 3200"
FLOOR=2800          # an anchor that cannot hold this is too low — stop the sweep
PASSES=6            # ~17 min per rung; overnight budget
SCREEN=0
WINDOWED=""
RESUME=0

usage() { sed -n '2,34p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --anchors) ANCHORS=$2; shift 2 ;;
    --clocks) CLOCKS=$2; shift 2 ;;
    --floor) FLOOR=$2; shift 2 ;;
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
[ -x "$FLATTEN" ] && [ -x "$SOAK" ] || { echo "gpu-flatten.sh / gpu-soak.sh missing" >&2; exit 1; }
NVCURVE="$home/.local/bin/nvcurve"
STATE="${home}/bench/explore-state.tsv"
mkdir -p "$(dirname "$STATE")"
say() { echo "$*" | tee -a "${STATE%.tsv}.log"; sync; }

if [ "$RESUME" = 1 ]; then
  [ -f "$STATE" ] || { echo "no state file at $STATE" >&2; exit 1; }
  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1} $2=="FINISHED"{if($1==s) s=""} END{print s}' "$STATE")
  say ""; say "═══ RESUME ═══"
  [ -n "$HUNG" ] && say "❌ ${HUNG} was STARTED but never finished — it hung the machine." \
                 || say "No incomplete rung — the last run ended cleanly."
  say ""; say "Passing pairs so far:"
  awk -F'\t' '$2=="FINISHED" && $3=="PASS" && $1!="stock"{print "  " $1}' "$STATE" | tee -a "${STATE%.tsv}.log"
  say ""; say "Full table:  ./tools/gpu-ladder-report.sh --state $STATE"; exit 0
fi

cleanup() { [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1; echo "curve reset to stock."; }
trap cleanup EXIT INT TERM

: > "$STATE"
say "=== two-axis undervolt exploration (unattended) ==="
say "anchors: $ANCHORS mV      clocks: $CLOCKS MHz"
say "floor:   $FLOOR MHz — an anchor that cannot hold this ends the sweep"
say "soak:    $PASSES passes per rung (~$(( PASSES * 167 / 60 )) min)"
say "state:   $STATE   (synced before every attempt — resume with --resume)"
say ""
say "Not a grid: lower voltage cannot hold MORE clock, so each lower anchor starts from"
say "the previous anchor's maximum and walks DOWN to the first rung that passes."
say ""

run_rung() {   # $1 = label
  printf '%s\tSTARTED\t\t%s\n' "$1" "$(date -Is)" >> "$STATE"; sync
  "$SOAK" --passes "$PASSES" --screen "$SCREEN" $WINDOWED >/dev/null 2>&1
  local rc=$?
  case "$rc" in
    0) printf '%s\tFINISHED\tPASS\t%s\n' "$1" "$(date -Is)" >> "$STATE" ;;
    2) printf '%s\tFINISHED\tINCONCLUSIVE\t%s\n' "$1" "$(date -Is)" >> "$STATE" ;;
    *) printf '%s\tFINISHED\tFAIL\t%s\n' "$1" "$(date -Is)" >> "$STATE" ;;
  esac
  sync; return $rc
}

# ── baseline ────────────────────────────────────────────────────────────────────────
say "───────────────────────────────────────────────"
say "BASELINE — stock   ($(date +%H:%M:%S))"
"$NVCURVE" write --reset >/dev/null 2>&1
run_rung "stock" || { say "baseline FAILED — unstable at stock. Stop and investigate."; exit 1; }
say "  ✓ baseline recorded"

CLOCK_LIST=$(echo "$CLOCKS" | tr ' ' '\n' | sort -n | tr '\n' ' ')
CEILING=""          # highest clock known to pass at the previous (higher) anchor

for mv in $ANCHORS; do
  say ""
  say "───────────────────────────────────────────────"
  say "ANCHOR ${mv} mV   ($(date +%H:%M:%S))"
  BEST_AT_ANCHOR=""

  if [ -z "$CEILING" ]; then
    # first anchor: climb until failure
    for mhz in $CLOCK_LIST; do
      say "  trying ${mhz} MHz ..."
      "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || { say "    flatten refused — skipping"; continue; }
      if run_rung "${mv}mV/${mhz}"; then say "    ✓ passed"; BEST_AT_ANCHOR=$mhz
      else say "    ✗ failed — anchor maximum is ${BEST_AT_ANCHOR:-none}"; break; fi
      "$NVCURVE" write --reset >/dev/null 2>&1
    done
  else
    # lower anchor: start at the previous maximum and walk DOWN to the first pass
    for mhz in $(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -rn | awk -v c="$CEILING" '$1<=c'); do
      say "  trying ${mhz} MHz ..."
      "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || { say "    flatten refused — skipping"; continue; }
      if run_rung "${mv}mV/${mhz}"; then say "    ✓ passed — anchor maximum ${mhz}"; BEST_AT_ANCHOR=$mhz; break
      else say "    ✗ failed — stepping down"; fi
      "$NVCURVE" write --reset >/dev/null 2>&1
    done
  fi

  "$NVCURVE" write --reset >/dev/null 2>&1
  if [ -z "$BEST_AT_ANCHOR" ]; then
    say "  ${mv} mV holds nothing at or above ${FLOOR} MHz — this voltage is too low."
    say "  Ending the sweep; lower anchors can only be worse."
    break
  fi
  CEILING=$BEST_AT_ANCHOR
  say "  → ${mv} mV maximum: ${BEST_AT_ANCHOR} MHz"
done

say ""
say "═══════════════════════════════════════════════"
say "SWEEP COMPLETE — $(date +%H:%M:%S)"
say ""
"$HERE/gpu-ladder-report.sh" --state "$STATE" 2>&1 | tee -a "${STATE%.tsv}.log"
say ""
say "The report above names the best pair. Apply it, then back off one rung for margin:"
say "  sudo $FLATTEN --mv <anchor> --mhz <clock>"
say "  sudo $NVCURVE profile save quiet"
say ""
say "Curve reset to stock. Nothing persists across a reboot."
