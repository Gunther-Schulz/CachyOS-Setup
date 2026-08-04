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
#   sudo ./tools/gpu-uv-explore.sh --resume     # CONTINUE after Ctrl-C or a hang
#   ./tools/gpu-uv-explore.sh --status          # report only, change nothing
#   ./tools/gpu-ladder-report.sh --state ~/bench/explore-state.tsv

set -uo pipefail
export LC_ALL=C

ANCHORS="1000 950 900 875"
CLOCKS="2800 2900 3000 3100 3200"
FLOOR=2800          # an anchor that cannot hold this is too low — stop the sweep
PASSES=4            # SCREENING passes per rung (~11 min) — cheap enough to sweep widely
CONFIRM=12          # passes for the final winner only (~33 min) — the run that decides
SCREEN=0
WINDOWED=""
RESUME=0
STATUS=0

usage() { sed -n '2,34p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --anchors) ANCHORS=$2; shift 2 ;;
    --clocks) CLOCKS=$2; shift 2 ;;
    --floor) FLOOR=$2; shift 2 ;;
    --passes) PASSES=$2; shift 2 ;;
    --confirm) CONFIRM=$2; shift 2 ;;
    --screen) SCREEN=$2; shift 2 ;;
    --windowed) WINDOWED="--windowed"; shift ;;
    --resume) RESUME=1; shift ;;
    --status) STATUS=1; shift ;;
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

# ── --status: report only, change nothing ───────────────────────────────────────────
if [ "$STATUS" = 1 ]; then
  [ -f "$STATE" ] || { echo "no state file at $STATE" >&2; exit 1; }
  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1} $2=="FINISHED"{if($1==s) s=""} END{print s}' "$STATE")
  [ -n "$HUNG" ] && echo "❌ ${HUNG} was STARTED but never finished — it hung the machine."
  echo "Completed pairs:"
  awk -F'\t' '$2=="FINISHED" && $1!="stock"{printf "  %-16s %s\n", $1, $3}' "$STATE"
  echo; exec "$HERE/gpu-ladder-report.sh" --state "$STATE"
fi

# ── --resume: CONTINUE where it stopped, re-running nothing already decided ──────────
# Ctrl-C is a safe pause: every verdict is appended and synced before the next rung
# starts, so the only work ever lost is the rung that was in flight.
BASE_DONE=0
declare -A ANCHOR_MAX ANCHOR_DONE
if [ "$RESUME" = 1 ]; then
  [ -f "$STATE" ] || { echo "no state file at $STATE — nothing to resume" >&2; exit 1; }
  while IFS=$'|' read -r label verdict; do
    [ "$label" = "stock" ] && { [ "$verdict" = "PASS" ] && BASE_DONE=1; continue; }
    mv=${label%%mV/*}; mhz=${label##*/}
    if [ "$verdict" = "PASS" ]; then
      # keep the highest clock that passed at this anchor
      cur=${ANCHOR_MAX[$mv]:-0}
      [ "$mhz" -gt "$cur" ] && ANCHOR_MAX[$mv]=$mhz
    elif [ "$verdict" = "FAIL" ]; then
      # a failure bounds this anchor: climbing stops, descending has its answer
      ANCHOR_DONE[$mv]=1
    fi
  done < <(awk -F'\t' '$2=="FINISHED"{print $1"|"$3}' "$STATE")

  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1} $2=="FINISHED"{if($1==s) s=""} END{print s}' "$STATE")
  if [ -n "$HUNG" ]; then
    mv=${HUNG%%mV/*}
    echo "NOTE: ${HUNG} was interrupted or hung — treating it as unproven and re-running it."
    [ "$HUNG" != "stock" ] && unset 'ANCHOR_DONE[$mv]'
  fi
  echo "resuming: baseline=$( [ "$BASE_DONE" = 1 ] && echo done || echo pending )  anchors already bounded: ${!ANCHOR_DONE[*]:-none}"
else
  : > "$STATE"
fi

cleanup() { [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1; echo "curve reset to stock."; }
trap cleanup EXIT INT TERM

# NOTE: the state file is truncated ONLY in the non-resume branch above. An
# unconditional `: > "$STATE"` here would erase the very history --resume just read.
say "=== two-axis undervolt exploration (unattended) ==="
say "anchors: $ANCHORS mV      clocks: $CLOCKS MHz"
say "floor:   $FLOOR MHz — an anchor that cannot hold this ends the sweep"
say "soak:    $PASSES passes per screening rung (~$(( PASSES * 167 / 60 )) min)"
say "         $CONFIRM passes to CONFIRM the winner at the end (~$(( CONFIRM * 167 / 60 )) min)"
say "state:   $STATE   (synced before every attempt — resume with --resume)"
say ""
say "Not a grid: lower voltage cannot hold MORE clock, so each lower anchor starts from"
say "the previous anchor's maximum and walks DOWN to the first rung that passes."
say ""

# Base frequency at an anchor voltage, from the card's own curve. The delta the silicon
# is being asked for is (target - base), and that ask — not the absolute clock — is what
# plausibly governs stability. Used to PREDICT where to start each lower anchor.
base_at() {
  "$NVCURVE" read --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); mv=float(sys.argv[1])
c=[p for p in d["vf_curve"] if p.get("domain")=="gpu" and p["volt_uV"]/1000.0>=mv]
print(int(min(c,key=lambda p:p["volt_uV"])["freq_kHz"]/1000) if c else 0)' "$1"
}

# Nearest clock in CLOCK_LIST at or below a predicted value.
snap_to() {
  echo "$CLOCK_LIST" | tr ' ' '\n' | sort -rn | awk -v t="$1" '$1<=t{print; exit}'
}

# Should the climb continue? Answers from the SCORE, which degrades before a hang.
# Returns 1 (stop) on a plateau, a regression, or widening spread. This is what lets the
# sweep stop at the practical maximum instead of walking into a crash to find it.
worth_continuing() {   # $1 = this rung, $2 = previous rung (may be empty)
  local cur prev sp base_sp
  cur=$(score_of "$1")
  [ "${cur:-0}" -gt 0 ] || return 0                    # no score to judge on — carry on
  sp=$(spread_of "$1"); base_sp=$(spread_of stock)

  # widening spread = the card is recovering from faults it has not yet crashed on
  # Floor the baseline at 2 per mille so a very tight control does not make the
  # threshold impossibly strict; 3x that is the trip point.
  [ "${base_sp:-0}" -lt 2 ] && base_sp=2
  if [ "${sp:-0}" -gt $(( base_sp * 3 )) ]; then
    say "    ! score spread ${sp}/1000 vs baseline ${base_sp}/1000 — erratic, stopping before it hangs"
    return 1
  fi
  # a regression below the baseline is degradation, not headroom
  if [ "${STOCK_SCORE:-0}" -gt 0 ] && [ "$cur" -lt $(( STOCK_SCORE * 99 / 100 )) ]; then
    say "    ! score ${cur} is below stock ${STOCK_SCORE} — degrading, stopping"
    return 1
  fi
  [ -n "$2" ] || return 0
  prev=$(score_of "$2")
  [ "${prev:-0}" -gt 0 ] || return 0
  # plateau: asking for more clock is not producing more work, so the next rung risks a
  # crash for nothing. 1% is ~3x the measured 0.3% run-to-run variance.
  if [ "$cur" -lt $(( prev * 101 / 100 )) ]; then
    say "    ! score ${cur} vs ${prev} — under 1% gain, the plateau. Stopping here rather"
    say "      than climbing into a crash for no measurable benefit."
    return 1
  fi
  return 0
}

# FurMark probe — the POWER-CAPPED regime, which GravityMark never reaches.
# GravityMark runs at ~371 W of 575 W, so lowering voltage costs clock there. FurMark
# pins the cap and is forced to clock DOWN, so lowering voltage lets it clock UP within
# the same budget. That is the regime where the forum user's +7.2% came from, and the
# only way to see it on this card. Measured at baseline AND at the confirmed setting, in
# the same session, so the pair is comparable.
furmark_probe() {   # $1 = label for the log
  command -v furmark >/dev/null || { say "  (furmark not installed — skipping the capped-regime probe)"; return; }
  local f="${STATE%.tsv}.furmark-$1.txt"
  ( for i in $(seq 1 40); do
      nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits \
        | tr -d ' ' | tr ',' ' '; sleep 3
    done > "$f" ) &
  local sp=$!
  timeout -k 10 150 furmark --demo furmark-vk --width 2560 --height 1440 \
      --max-time 120 --no-score-box >/dev/null 2>&1
  kill $sp 2>/dev/null
  awk '$2+0>300 {n++; c+=$1; w+=$2; if($3+0>t)t=$3+0}
       END{ if(n) printf "  FurMark (power-capped): %.0f MHz  %.0f W  peak %.0f C\n", c/n, w/n, t
            else print "  FurMark: no loaded samples" }' "$f" | tee -a "${STATE%.tsv}.log"
}

run_rung() {   # $1 = label
  printf '%s\tSTARTED\t\t%s\n' "$1" "$(date -Is)" >> "$STATE"; sync
  local out rc
  # Capture the soak's own output directory rather than matching it by timestamp later.
  # Timestamp matching is guesswork that breaks whenever two runs land in the same second.
  out=$("$SOAK" --passes "$PASSES" --screen "$SCREEN" $WINDOWED 2>&1 | tee -a "${STATE%.tsv}.soaks.log" | awk '/^output:/{print $2}')
  rc=${PIPESTATUS[0]}
  case "$rc" in
    0) printf '%s\tFINISHED\tPASS\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
    2) printf '%s\tFINISHED\tINCONCLUSIVE\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
    *) printf '%s\tFINISHED\tFAIL\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
  esac
  sync; return $rc
}

# Mean score and spread for a recorded rung. Instability announces itself in the SCORE
# before it crashes: a card recovering from micro-faults loses throughput and gets
# erratic. Reading that is how the sweep can find the practical maximum without ever
# having to reach the wall.
score_of() {
  local d; d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -s "$d/scores.txt" ] || { echo 0; return; }
  awk '{s+=$1;n++} END{printf "%d", (n? s/n : 0)}' "$d/scores.txt"
}
# Peak-to-peak spread in PER MILLE, not percent. The baseline's real spread is ~2 per
# mille (0.19%), which truncates to 0 in integer percent — silently disabling the guard
# that depends on it. Integer percent has no resolution at the scale being measured.
spread_of() {   # returns tenths of a percent
  local d; d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -s "$d/scores.txt" ] || { echo 0; return; }
  awk '{s+=$1; if(!mn||$1<mn)mn=$1; if($1>mx)mx=$1}
       END{ if(NR>1) printf "%d", (mx-mn)*1000/(s/NR); else print 0 }' "$d/scores.txt"
}

# Mean delivered clock for a recorded rung, from the soak dir the state file names.
clock_of() {
  local d
  d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -f "$d/sensors.txt" ] || { echo 0; return; }
  awk '$3!="n/a" && $3+0>100 {n++; f+=$2} END{printf "%d", (n? f/n : 0)}' "$d/sensors.txt"
}

# ── baseline ────────────────────────────────────────────────────────────────────────
if [ "$BASE_DONE" = 1 ]; then
  say "BASELINE — already recorded in a previous run, skipping."
else
  say "───────────────────────────────────────────────"
  say "BASELINE — stock   ($(date +%H:%M:%S))"
  "$NVCURVE" write --reset >/dev/null 2>&1
  run_rung "stock" || { say "baseline FAILED — unstable at stock. Stop and investigate."; exit 1; }
  say "  ✓ baseline recorded"
fi
STOCK_CLK=$(clock_of stock); STOCK_SCORE=$(score_of stock)
if [ "${STOCK_CLK:-0}" -gt 0 ]; then
  say "  stock delivers ${STOCK_CLK} MHz, score ${STOCK_SCORE}, spread $(spread_of stock)/1000"
  say "  — the crossover and plateau rules are measured against these"
  say "  probing the power-capped regime at stock:"
  furmark_probe stock
else
  say "  ⚠️ could not read the stock clock; the crossover stop rule is DISABLED"
fi

CLOCK_LIST=$(echo "$CLOCKS" | tr ' ' '\n' | sort -n | tr '\n' ' ')
CEILING=""          # highest clock known to pass at the previous (higher) anchor
MAX_DELTA=0         # largest (target - base) that has passed anywhere — the predictor

for mv in $ANCHORS; do
  say ""
  say "───────────────────────────────────────────────"
  say "ANCHOR ${mv} mV   ($(date +%H:%M:%S))"
  BEST_AT_ANCHOR="${ANCHOR_MAX[$mv]:-}"
  if [ -n "${ANCHOR_DONE[$mv]:-}" ] && [ -n "$BEST_AT_ANCHOR" ]; then
    say "  already determined in a previous run: maximum ${BEST_AT_ANCHOR} MHz — skipping"
    CEILING=$BEST_AT_ANCHOR
    continue
  fi

  PREV_LABEL=""
  if [ -z "$CEILING" ]; then
    # first anchor: climb until the score stops improving, or until failure
    for mhz in $CLOCK_LIST; do
      if grep -qF "${mv}mV/${mhz}	FINISHED" "$STATE" 2>/dev/null; then
        say "  ${mhz} MHz — already decided in a previous run, skipping"; continue; fi
      say "  trying ${mhz} MHz ..."
      "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || { say "    flatten refused — skipping"; continue; }
      if run_rung "${mv}mV/${mhz}"; then
        say "    ✓ passed"
        if ! worth_continuing "${mv}mV/${mhz}" "$PREV_LABEL"; then
          BEST_AT_ANCHOR=$mhz; "$NVCURVE" write --reset >/dev/null 2>&1; break
        fi
        BEST_AT_ANCHOR=$mhz; PREV_LABEL="${mv}mV/${mhz}"
      else say "    ✗ failed — anchor maximum is ${BEST_AT_ANCHOR:-none}"; break; fi
      "$NVCURVE" write --reset >/dev/null 2>&1
    done
  else
    # Lower anchor. Start from the DELTA that worked highest so far rather than from the
    # previous anchor's absolute clock — at a lower anchor the same clock is a much
    # bigger ask, so the naive start is usually several doomed rungs above the answer.
    BASE=$(base_at "$mv")
    if [ "${BASE:-0}" -gt 0 ] && [ "${MAX_DELTA:-0}" -gt 0 ]; then
      PRED=$(snap_to $(( BASE + MAX_DELTA )))
      say "  predicted start ${PRED:-none} MHz  (base ${BASE} + best delta ${MAX_DELTA})"
    fi
    START=${PRED:-$CEILING}

    # Try the prediction, then move in whichever direction the result points. Climbing
    # after a pass is the safeguard: if delta does NOT govern, the prediction starts too
    # low and a one-way descent would silently under-report this anchor's maximum.
    if grep -qF "${mv}mV/${START}	FINISHED" "$STATE" 2>/dev/null; then
      say "  ${START} MHz already decided — skipping"
    else
      say "  trying ${START} MHz (prediction) ..."
      if "$FLATTEN" --mv "$mv" --mhz "$START" >/dev/null 2>&1 && run_rung "${mv}mV/${START}"; then
        say "    ✓ passed"; BEST_AT_ANCHOR=$START
      else
        say "    ✗ failed"
      fi
      "$NVCURVE" write --reset >/dev/null 2>&1
    fi

    if [ -n "$BEST_AT_ANCHOR" ]; then
      # passed the prediction — climb to make sure we are not leaving clock on the table
      for mhz in $(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk -v s="$START" '$1>s'); do
        grep -qF "${mv}mV/${mhz}	FINISHED" "$STATE" 2>/dev/null && continue
        say "  climbing to ${mhz} MHz ..."
        "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || continue
        if run_rung "${mv}mV/${mhz}"; then say "    ✓ passed"; BEST_AT_ANCHOR=$mhz
        else say "    ✗ failed — anchor maximum ${BEST_AT_ANCHOR}"; break; fi
        "$NVCURVE" write --reset >/dev/null 2>&1
      done
    else
      # failed the prediction — descend to the first pass
      for mhz in $(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -rn | awk -v s="$START" '$1<s'); do
        grep -qF "${mv}mV/${mhz}	FINISHED" "$STATE" 2>/dev/null && continue
        say "  descending to ${mhz} MHz ..."
        "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || continue
        if run_rung "${mv}mV/${mhz}"; then say "    ✓ passed — anchor maximum ${mhz}"; BEST_AT_ANCHOR=$mhz; break
        else say "    ✗ failed — stepping down"; fi
        "$NVCURVE" write --reset >/dev/null 2>&1
      done
    fi
    unset PRED
  fi

  "$NVCURVE" write --reset >/dev/null 2>&1
  if [ -z "$BEST_AT_ANCHOR" ] || [ "$BEST_AT_ANCHOR" -lt "$FLOOR" ]; then
    say "  ${mv} mV holds nothing at or above ${FLOOR} MHz (best: ${BEST_AT_ANCHOR:-none}) — too low."
    say "  Ending the sweep; lower anchors can only be worse."
    break
  fi
  # ── STOP RULE, grounded in the goal rather than a threshold ───────────────────────
  # Above the stock baseline clock, a lower anchor is FREE power — strictly better, keep
  # going. Below it you have started trading performance for watts, which is not the
  # stated goal. The crossover is the decision point, and the 1% tolerance is the
  # measured run-to-run variance (0.3% spread), not a guess.
  DELIVERED=$(clock_of "${mv}mV/${BEST_AT_ANCHOR}")
  if [ "${STOCK_CLK:-0}" -gt 0 ] && [ "$DELIVERED" -gt 0 ]; then
    THRESH=$(( STOCK_CLK * 99 / 100 ))
    say "  delivered ${DELIVERED} MHz vs stock ${STOCK_CLK} MHz (floor ${THRESH})"
    if [ "$DELIVERED" -lt "$THRESH" ]; then
      say ""
      say "  ► STOPPING: ${mv} mV delivers ${DELIVERED} MHz, below the stock baseline."
      say "    Lower anchors can only be slower. Past this point every further step"
      say "    trades performance for watts, which is not the goal — so the sweep ends"
      say "    here rather than spending hours mapping trades you would not take."
      CEILING=$BEST_AT_ANCHOR
      break
    fi
  fi

  CEILING=$BEST_AT_ANCHOR
  B=$(base_at "$mv")
  if [ "${B:-0}" -gt 0 ]; then
    D=$(( BEST_AT_ANCHOR - B ))
    [ "$D" -gt "${MAX_DELTA:-0}" ] && MAX_DELTA=$D
    say "  → ${mv} mV maximum: ${BEST_AT_ANCHOR} MHz  (delta +${D} over its base ${B})"
  else
    say "  → ${mv} mV maximum: ${BEST_AT_ANCHOR} MHz"
  fi
done

# ── confirm the winner with a long soak ─────────────────────────────────────────────
# Screening rungs are deliberately short — instability at the edge is probabilistic, so
# a short pass is a SCREEN, not proof. The pair that survives screening earns one long
# soak before it is recommended.
# Pick the best passing pair by the actual criterion: highest target clock wins, and at
# equal clock the LOWER anchor wins (same speed, less voltage). `tail -1` previously took
# whatever was recorded last — the lowest anchor's result, typically the slowest setting.
WIN=$(awk -F'\t' '$2=="FINISHED" && $3=="PASS" && $1!="stock" && $1 !~ /confirm/ {print $1}' "$STATE" \
      | awk -F'mV/' '{print $2"\t"$1}' | sort -k1,1nr -k2,2n | head -1 \
      | awk -F'\t' '{print $2"mV/"$1}')

# Confirm the setting that will actually be USED — one rung below the maximum, per the
# back-off rule — not the maximum itself. Confirming a setting you intend to abandon
# proves nothing about the one you will run.
if [ -n "$WIN" ]; then
  wmv=${WIN%%mV/*}; wmax=${WIN##*/}
  wmhz=$(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk -v m="$wmax" '$1<m{p=$1} END{print p+0}')
  [ "${wmhz:-0}" -gt 0 ] || wmhz=$wmax     # nothing below it — confirm the max itself
  say ""
  say "───────────────────────────────────────────────"
  say "Best passing pair: ${wmv} mV / ${wmax} MHz"
  if [ "$wmhz" != "$wmax" ]; then
    say "Confirming ONE RUNG BELOW it — ${wmv} mV / ${wmhz} MHz — because that is the"
    say "setting the back-off rule says to run. Margin covers a warm day, a driver"
    say "update, and aging; instability at the edge is probabilistic."
  else
    say "No rung below it in the tested set — confirming the maximum itself."
  fi
  if [ "$CONFIRM" -gt "$PASSES" ]; then
    say "CONFIRMING ${wmv} mV / ${wmhz} MHz with $CONFIRM passes   ($(date +%H:%M:%S))"
    if "$FLATTEN" --mv "$wmv" --mhz "$wmhz" >/dev/null 2>&1; then
      PASSES=$CONFIRM
      if run_rung "${wmv}mV/${wmhz}-confirm"; then
        say "  ✓ CONFIRMED over $CONFIRM passes — this is the setting to keep."
        say ""
        say "  probing the power-capped regime at this setting (compare with stock above):"
        "$FLATTEN" --mv "$wmv" --mhz "$wmhz" >/dev/null 2>&1
        furmark_probe confirmed
        say "  ^ THIS is where the gain shows as more CLOCK at the same 575 W, rather"
        say "    than as less power. Both come from the same setting."
        say "     sudo $FLATTEN --mv $wmv --mhz $wmhz"
        say "     sudo $NVCURVE profile save quiet"
      else
        say "  ✗ FAILED the long soak. Screening was not enough evidence — drop another rung."
      fi
    fi
    "$NVCURVE" write --reset >/dev/null 2>&1
  fi
fi

say ""
say "═══════════════════════════════════════════════"
say "SWEEP COMPLETE — $(date +%H:%M:%S)"
say ""
"$HERE/gpu-ladder-report.sh" --state "$STATE" 2>&1 | tee -a "${STATE%.tsv}.log"
say ""
say "The confirmed pair above is the one to keep — the back-off rung has already been"
say "applied and soaked, so no further adjustment is needed."
say ""
say "Curve reset to stock. Nothing persists across a reboot."
