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

echo
if [ "$FAIL" -eq 0 ]; then echo "✅ all $PASS selection cases pass"; exit 0
else echo "❌ $FAIL of $((PASS+FAIL)) cases FAILED"; exit 1; fi
