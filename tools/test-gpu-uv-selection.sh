#!/usr/bin/env bash
# test-gpu-uv-selection.sh — regression test for gpu-uv-explore.sh's winner selection.
#
# WHY THIS EXISTS. The selection rule has been wrong twice, both times silently — it
# printed a confident recommendation that was simply the wrong setting:
#
#   bug 1 (fixed 2026-08-04): `tail -1` took whatever was recorded last, typically the
#          SLOWEST setting.
#   bug 2 (fixed 2026-08-04): ranking by TARGET CLOCK picked 1000mV/3100, which passed a
#          clean 4-pass soak while scoring 3.1% BELOW 1000mV/3000 — the card stretches
#          the clock internally and nvidia-smi keeps reporting the requested value, so a
#          rung can be stable, report a higher clock, and deliver less work.
#   bug 3 (fixed 2026-08-04): applying the back-off AFTER ranking demoted the winner
#          below a rival it had just beaten.
#
# None of these crash, and none show up in a soak — the run completes and recommends the
# wrong thing. Only a fixture with known-correct answers catches them, which is what this
# is. Fixtures are self-contained; nothing here reads ~/bench or touches the GPU.
#
# Usage:  ./tools/test-gpu-uv-selection.sh          # no root, no hardware

set -uo pipefail
export LC_ALL=C

HERE=$(cd "$(dirname "$0")" && pwd)
SUT="$HERE/gpu-uv-explore.sh"
[ -f "$SUT" ] || { echo "cannot find $SUT" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# Extract the selection block from the real script rather than restating it here — a copy
# would pass forever while the script it claims to test drifted away underneath it.
SEL="$TMP/sel.sh"
sed -n '/^RUNGS=\$(while/,/^WIN=\$(echo "\$WIN_ROW"/p' "$SUT" > "$SEL"
[ -s "$SEL" ] || { echo "FATAL: could not extract the selection block from $SUT" >&2
                   echo "       (the anchors changed — fix this test, do not delete it)" >&2; exit 1; }

score_of() {
  local d; d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -s "$d/scores.txt" ] || { echo 0; return; }
  awk '{s+=$1;n++} END{printf "%d", (n? s/n : 0)}' "$d/scores.txt"
}

# build a fixture: rung|score|verdict triples -> a state file with backing score dirs
fixture() {   # $1 = case name, then rung:score:verdict ...
  local name=$1; shift
  STATE="$TMP/$name.tsv"; : > "$STATE"
  printf 'stock\tFINISHED\tPASS\t-\t%s\n' "$(scoredir "$name" stock 76896)" >> "$STATE"
  local spec rung sc v
  for spec in "$@"; do
    IFS=: read -r rung sc v <<< "$spec"
    printf '%s\tFINISHED\t%s\t-\t%s\n' "$rung" "$v" "$(scoredir "$name" "$rung" "$sc")" >> "$STATE"
  done
}
scoredir() {  # a dir whose 4 scores average to $3
  local d="$TMP/$1-$(echo "$2" | tr / _)"; mkdir -p "$d"
  printf '%s\n%s\n%s\n%s\n' "$3" "$3" "$3" "$3" > "$d/scores.txt"; echo "$d"
}

check() {   # $1 = case name, $2 = expected WIN, $3 = expected confirmed MHz, $4 = why
  # shellcheck disable=SC1090
  . "$SEL"
  local got_win="$WIN" got_mhz
  local wmv=${WIN%%mV/*} wmax=${WIN##*/}
  if [ -n "${COVERED_WIN:-}" ]; then
    got_mhz=$wmax
  else
    got_mhz=$(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk -v m="$wmax" '$1<m{p=$1} END{print p+0}')
    [ "${got_mhz:-0}" -gt 0 ] || got_mhz=$wmax
  fi
  if [ "$got_win" = "$2" ] && [ "$got_mhz" = "$3" ]; then
    printf '  ✅ %-26s -> %s, confirms %s MHz\n' "$1" "$got_win" "$got_mhz"; PASS=$((PASS+1))
  else
    printf '  ❌ %-26s -> got %s/%s MHz, expected %s/%s MHz\n' "$1" "$got_win" "$got_mhz" "$2" "$3"
    printf '     %s\n' "$4"; FAIL=$((FAIL+1))
  fi
  unset COVERED_WIN
}

echo "=== gpu-uv-explore.sh winner selection ==="
CLOCK_LIST="2800 2900 3000 3100 3200"

# ── the real 2026-08-04 ladder ──────────────────────────────────────────────────────
# 1000mV/3100 PASSED but is 3.1% slower (clock stretching). 950mV/3100 hard-locked, so
# 950's ceiling is 3000 and 950mV/3000 has no proven margin above it.
fixture real \
  1000mV/2800:77137:PASS 1000mV/2900:79560:PASS 1000mV/3000:82329:PASS \
  1000mV/3100:79778:PASS 950mV/3000:82400:PASS
check "real ladder" 1000mV/3000 3000 \
  "must not pick the stretched 3100, nor 950mV/3000 which would back off to an untested 2900"

# ── a stable rung that scores LESS must never win ───────────────────────────────────
fixture stretched 1000mV/3000:82329:PASS 1000mV/3100:79778:PASS
check "stretched top rung" 1000mV/3000 3000 \
  "3100 passed but delivers less work — score decides, not the reported clock"

# ── nothing covered: fall back to backing off from the best ─────────────────────────
fixture nomargin 950mV/3000:82400:PASS
check "no covered rung" 950mV/3000 2900 \
  "top rung at its anchor with nothing proven above -> back off one rung"

# ── equal scores: the lower anchor wins (same speed, less voltage) ──────────────────
fixture tie 1000mV/2900:80000:PASS 1000mV/3000:80000:PASS 1000mV/3100:80000:PASS \
            950mV/2900:80000:PASS 950mV/3000:80000:PASS 950mV/3100:80000:PASS
check "tie -> lower anchor" 950mV/3000 3000 \
  "identical scores must resolve to the lowest anchor at the highest covered clock"

# ── a FAILED rung sets no ceiling, so the rung below it is not 'covered' ────────────
fixture failceil 1000mV/3000:82329:PASS 1000mV/3100:0:FAIL
check "failed rung is no ceiling" 1000mV/3000 2900 \
  "a rung that FAILED cannot supply margin — the one below it must back off"


# ── the clock-stretching detector ───────────────────────────────────────────────────
# Fires on: score DOWN >1%, reported clock UP, power DOWN. All three are required.
# Power is what makes it distinguishable from noise — at a fixed voltage ceiling power
# goes as f*V^2, so a genuine clock rise must cost power. Clock up + power down + score
# down is a combination a really-faster rung cannot produce.
echo
echo "=== clock-stretching detector ==="

stretch() {   # cur_score prev_score cur_clk prev_clk cur_W prev_W  -> 0 = fires
  [ "$1" -lt $(( $2 * 99 / 100 )) ] && [ "$3" -gt "$4" ] && [ "$6" -gt 0 ] && [ "$5" -lt "$6" ]
}
scase() {   # name expect(fire|quiet) then the six numbers
  local name=$1 expect=$2; shift 2
  local got=quiet; stretch "$@" && got=fire
  if [ "$got" = "$expect" ]; then printf '  ✅ %-30s %s\n' "$name" "$got"; PASS=$((PASS+1))
  else printf '  ❌ %-30s got %s, expected %s\n' "$name" "$got" "$expect"; FAIL=$((FAIL+1)); fi
}

# the real 2026-08-04 defect: 1000mV/3100 against 1000mV/3000
scase "real: 3100 after 3000"      fire  79778 82329 2881 2802 327 333
# real legitimate gain below it: 1000mV/3000 after 1000mV/2900 — must stay quiet
scase "real: 3000 after 2900"      quiet 82329 79560 2802 2743 333 327
# a rung that is simply slower AND draws more power is not stretching, it is just worse
scase "slower but power UP"        quiet 79000 82329 2881 2802 340 333
# slower with the clock DOWN is an ordinary regression, not stretching
scase "slower, clock down"         quiet 79000 82329 2750 2802 327 333
# within the 1% noise band: not a finding in either direction
scase "0.5% drop is noise"         quiet 81900 82329 2881 2802 327 333
# no previous power reading (first rung) must not fire on a divide-by-nothing
scase "no previous power"          quiet 79778 82329 2881 2802 327 0


# ── the proven-delta cap ────────────────────────────────────────────────────────────
# THE HARD LOCK OF 2026-08-04 18:49. At 900 mV: base 2002, best proven delta +435, so the
# prediction was 2437 MHz — below the entire clock list (floor 2700). snap_to correctly
# returned empty, and `START=${PRED:-$CEILING}` then reached for the CEILING: 3100 MHz,
# a delta of +1098 where +435 was the most ever proven. gpu-flatten.sh refused that one
# (its own +/-1000 cap), the refusal was misread as a rung failure, and the descend path
# found the first clock the cap would ACCEPT — 3000 MHz, delta +998. The machine died.
#
# The lesson pinned here: a prediction below the clock list is an ANSWER ("this anchor
# cannot reach the floor"), not a missing value to paper over with the most aggressive
# rung available. And "the flatten accepted it" is not evidence of safety.
echo
echo "=== proven-delta cap (the 18:49 hard lock) ==="

plan() {   # base max_delta clock_list floor ceiling -> what the sweep would attempt
  local BASE=$1 MAX_DELTA=$2 CLOCK_LIST=$3 FLOOR=$4 CEILING=$5 STEP PRED DELTA_CAP START
  snap_to() { echo "$CLOCK_LIST" | tr ' ' '\n' | sort -rn | awk -v t="$1" '$1<=t{print; exit}'; }
  STEP=$(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk 'NR>1{d=$1-p; if(!m||d<m)m=d} {p=$1} END{print (m?m:100)}')
  DELTA_CAP=0
  if [ "$BASE" -gt 0 ] && [ "$MAX_DELTA" -gt 0 ]; then
    DELTA_CAP=$(( BASE + MAX_DELTA + STEP ))
    PRED=$(snap_to $(( BASE + MAX_DELTA )))
    if [ "$DELTA_CAP" -lt "$FLOOR" ]; then echo "SKIP-ANCHOR"; return; fi
  fi
  START=${PRED:-$CEILING}
  if [ "$DELTA_CAP" -gt 0 ] && [ "$START" -gt "$DELTA_CAP" ]; then
    START=$(snap_to "$DELTA_CAP"); [ -n "$START" ] || { echo "SKIP-ANCHOR"; return; }
  fi
  echo "$START"
}
pcase() {   # name expected base delta clocks floor ceiling
  local name=$1 expect=$2; shift 2
  local got; got=$(plan "$@")
  if [ "$got" = "$expect" ]; then printf '  ✅ %-34s %s\n' "$name" "$got"; PASS=$((PASS+1))
  else printf '  ❌ %-34s got %s, expected %s\n' "$name" "$got" "$expect"; FAIL=$((FAIL+1)); fi
}

# the exact crash: must refuse the anchor outright, not reach for the ceiling
pcase "900mV/435 delta (the real crash)" SKIP-ANCHOR 2002 435 "2700 2800 2900 3000 3100" 2700 3100
# a prediction inside the list: use it, unchanged
pcase "950mV — prediction in range"      3000        2580 435 "2700 2800 2900 3000 3100" 2700 3100
# A prediction inside the list is USED as-is; the cap only binds when it is not.
pcase "prediction wins over the cap"     2700        2300 435 "2700 2800 2900 3000 3100" 2700 3100
# The reduction path: prediction falls below the list, but the cap still clears the floor,
# so the ceiling must be pulled DOWN to the cap instead of used raw. This is the exact
# shape of the crash, one step less severe — the case where the anchor is still viable.
pcase "ceiling above cap is reduced"     2700        2250 400 "2700 2800 2900 3000 3100" 2700 3100
# no delta knowledge yet (first anchor): ceiling is the only guide, cap inactive
pcase "no proven delta -> ceiling"       3100        2002 0   "2700 2800 2900 3000 3100" 2700 3100

echo
if [ "$FAIL" -eq 0 ]; then echo "✅ all $PASS cases pass"; exit 0
else echo "❌ $FAIL of $((PASS+FAIL)) cases FAILED"; exit 1; fi
