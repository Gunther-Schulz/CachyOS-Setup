#!/usr/bin/env bash
# gpu-quiet-sweep.sh — find the LOWEST power limit that still holds full performance.
#
# THE GOAL IS QUIET, NOT FAST. That inverts the usual undervolt recipe, and the
# reasoning matters because the obvious approach does not work:
#
#   * Undervolt ALONE cannot make this card cooler. Under a fixed power cap the card
#     spends its whole budget regardless; freed voltage is converted into more clock at
#     the same watts. Measured 2026-08-04: +300 MHz offset bought ~+2% clock and ZERO
#     temperature benefit. Heat is set by the power limit, not by the curve.
#   * Power limit ALONE makes it cooler but slower — a straight performance cut.
#   * BOTH TOGETHER is the answer: lower the cap for the heat reduction, and let the
#     V/F offset recover the clock the cap took away. Same performance, less heat.
#
# So this holds the offset FIXED at a value already proven stable and sweeps the POWER
# LIMIT downward, looking for the knee — the lowest wattage that still delivers full
# performance. That setting is the one worth persisting.
#
# Metrics: benchmark score (the thing you care about), peak temperature and FAN RPM
# (the thing you actually hear), sampled DURING the load, with every run started from
# the same temperature so steps are comparable.
#
# Usage (needs root — nvidia-smi -pl and nvcurve writes require it):
#   sudo ./tools/gpu-quiet-sweep.sh --offset 250
#   sudo ./tools/gpu-quiet-sweep.sh --offset 250 --limits "575 525 475 425 375"
#   sudo ./tools/gpu-quiet-sweep.sh --offset 0 --limits 575        # stock reference only
#   sudo ./tools/gpu-quiet-sweep.sh --reset                        # undo everything
#
# THE LOAD IS DRIVEN BY YOU. Each step prints "START THE BENCHMARK NOW", samples for
# --dur seconds, then waits for you to press Enter with the score. GravityMark is a GUI
# benchmark and its score is the metric — no script can read it off the screen.
#
# Nothing persists: nvcurve offsets and nvidia-smi -pl are both runtime state, cleared
# by a reboot. The script also restores stock on exit, including on Ctrl-C.

set -uo pipefail
export LC_ALL=C          # awk emits "68.6", bash printf expects "68,6" on this machine

OFFSET=250
LIMITS="575 525 475 425 375"
DUR=180
COOL_TO=50               # cool to this core temp before each run — NOT a fixed sleep
COOL_MAX=420             # give up waiting after this many seconds
DO_RESET=0

usage() { sed -n '2,34p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --offset) OFFSET=$2; shift 2 ;;
    --limits) LIMITS=$2; shift 2 ;;
    --dur) DUR=$2; shift 2 ;;
    --cool-to) COOL_TO=$2; shift 2 ;;
    --reset) DO_RESET=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (nvidia-smi -pl, nvcurve); re-run with sudo" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
NVCURVE="$home/.local/bin/nvcurve"
[ -x "$NVCURVE" ] || NVCURVE=$(command -v nvcurve 2>/dev/null) || true
SENSORS="$home/dev/vendor/nvidia-gpu-sensors/build/nvidia-gpu-sensors"

DEFAULT_PL=$(nvidia-smi --query-gpu=power.default_limit --format=csv,noheader,nounits | tr -d ' ')

restore() {
  echo
  echo "restoring stock: power limit ${DEFAULT_PL} W, offsets 0 ..."
  nvidia-smi -pl "${DEFAULT_PL%.*}" >/dev/null 2>&1
  [ -n "${NVCURVE:-}" ] && [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1
  echo "done — nothing persists."
}
trap restore EXIT INT TERM

if [ "$DO_RESET" = 1 ]; then exit 0; fi   # trap does the work

# --- sensors -------------------------------------------------------------------------
MB=""
for h in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$h/name" 2>/dev/null)" = nct6799 ] && { MB="$h"; break; }
done
# fan1 = Arctic P12 case fans, header reports 2 tach pulses/rev so raw is ~2x actual;
# fan2 = Silent Wings 4 on the AIO. Channel map: fan-control/coolercontrol-labels.md
core_temp() { nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | tr -d ' '; }

sample_line() {
  local smi hot=n/a
  smi=$(nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu,fan.speed,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' ' ')
  # hotspot + memory junction are invisible to nvidia-smi on Blackwell; nvidia-gpu-sensors
  # reads them through the driver's own ioctl. Optional — degrade rather than fail.
  if [ -x "$SENSORS" ]; then
    hot=$("$SENSORS" 2>/dev/null | awk '$1=="0"{n=0;i=2; while(i<=NF){ if($i=="n/a"){v[n++]="n/a";i++} else {v[n++]=$i;i+=2} } print v[2]}')
  fi
  local c=n/a a=n/a
  [ -n "$MB" ] && { c=$(( $(cat "$MB/fan1_input" 2>/dev/null || echo 0) / 2 )); a=$(cat "$MB/fan2_input" 2>/dev/null || echo 0); }
  echo "$(date +%s) ${smi:-n/a n/a n/a n/a n/a} ${hot:-n/a} $c $a"
}

sampler() { while :; do sample_line; sleep 2; done > "$1"; }

# max of column $c, ignoring n/a. `seen` not decoration: a real ZERO is data (a stopped
# fan reads 0), and testing the accumulated max would report it as missing.
cmax() { awk -v c="$1" '$c!="n/a"{v=$c+0; if(!s||v>m){m=v;s=1}} END{if(s) printf "%.0f", m; else print "n/a"}' "$2"; }
cmean() { awk -v c="$1" '$c!="n/a"{s+=$c;n++} END{if(n) printf "%.0f", s/n; else print "n/a"}' "$2"; }

cool_down() {   # wait for TEMPERATURE, not a fixed sleep — this is what makes steps comparable
  local t waited=0
  t=$(core_temp)
  [ "${t:-99}" -le "$COOL_TO" ] && { echo "    already at ${t} C"; return; }
  printf '    cooling to %s C ' "$COOL_TO"
  while [ "$waited" -lt "$COOL_MAX" ]; do
    t=$(core_temp); [ "${t:-99}" -le "$COOL_TO" ] && { echo " reached ${t} C after ${waited}s"; return; }
    printf '.'; sleep 10; waited=$((waited+10))
  done
  echo " gave up at ${t} C after ${COOL_MAX}s — steps may not be comparable"
}

OUT="${home:-/root}/bench/quiet-sweep-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "cannot create $OUT" >&2; exit 1; }
LOG="$OUT/progress.log"
say() { echo "$*" | tee -a "$LOG"; sync; }

say "=== GPU quiet sweep — lowest power limit that still holds performance ==="
say "V/F offset held FIXED at +${OFFSET} MHz (must already be proven stable)"
say "power limits to test: $LIMITS W"
say "per step: cool to ${COOL_TO} C, then sample ${DUR}s during YOUR benchmark run"
say "output: $OUT"
say ""
say "Goal is QUIET. An undervolt alone cannot cool a power-capped card — it converts"
say "freed voltage into clock at the same watts. Lowering the cap is what removes heat;"
say "the offset is what stops that costing performance."
say ""

if [ -n "${NVCURVE:-}" ] && [ -x "$NVCURVE" ] && [ "$OFFSET" -ne 0 ]; then
  "$NVCURVE" write --global --delta "$OFFSET" >"$OUT/offset.log" 2>&1 \
    && say "V/F offset +${OFFSET} MHz applied." || { say "FAILED to apply offset — aborting."; exit 1; }
fi

printf 'watt_limit\tscore\tpeak_C\thotspot_C\tmean_MHz\tmean_W\tgpu_fan%%\tcase_rpm\taio_rpm\n' > "$OUT/results.tsv"

for W in $LIMITS; do
  say "───────────────────────────────────────────────"
  say "POWER LIMIT ${W} W   (offset +${OFFSET})"
  nvidia-smi -pl "$W" >/dev/null 2>&1 || { say "  could not set ${W} W — skipping"; continue; }
  cool_down

  say ""
  say "  ►►► START THE BENCHMARK NOW  (GravityMark, Vulkan RT, 2K, 200 000) ◄◄◄"
  say "      sampling for ${DUR}s ..."
  f="$OUT/samples-${W}w.txt"
  sampler "$f" & p=$!
  sleep "$DUR"
  kill $p 2>/dev/null

  say "  peak core $(cmax 4 "$f") C   hotspot $(cmax 6 "$f") C   mean $(cmean 2 "$f") MHz   mean $(cmean 3 "$f") W"
  say "  fans: GPU $(cmax 5 "$f")%   case $(cmax 7 "$f") rpm   AIO $(cmax 8 "$f") rpm"
  printf '  enter the benchmark SCORE (or blank to skip): ' | tee -a "$LOG"
  read -r SCORE < /dev/tty
  SCORE=${SCORE:-n/a}
  say "  score: $SCORE"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$W" "$SCORE" "$(cmax 4 "$f")" "$(cmax 6 "$f")" \
    "$(cmean 2 "$f")" "$(cmean 3 "$f")" "$(cmax 5 "$f")" "$(cmax 7 "$f")" "$(cmax 8 "$f")" >> "$OUT/results.tsv"
done

say ""
say "═══════════════════════════════════════════════"
column -t "$OUT/results.tsv" | tee -a "$LOG"
say ""
say "READ IT LIKE THIS: walk DOWN the wattage column and find the last row whose score"
say "is still within ~2% of the top one. That is the knee — the lowest power limit that"
say "costs you nothing measurable, and the quietest setting worth keeping. Below it you"
say "are trading real performance for silence, which may still be a fine trade — but it"
say "is a different decision, and one you should make deliberately."
say ""
say "Fan RPM is the column that answers the actual complaint. Score answers the cost."
say ""
say "To keep a setting (runtime only, gone on reboot):"
say "  sudo nvidia-smi -pl <watts>"
say "  sudo $NVCURVE write --global --delta $OFFSET"
say "Persisting it across reboots is a SEPARATE step, taken only after a long soak and"
say "real gameplay — see docs/cachyos/todo.md."
