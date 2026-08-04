#!/usr/bin/env bash
# gpu-thermal.sh — RTX 5090 thermal test: idle baseline → sustained load → peaks.
#
# The GPU counterpart to thermal-sweep.sh. What it exists to measure is the
# HOTSPOT-MINUS-CORE delta under sustained load, which is the number that
# distinguishes a bad die mount / pump-out / dried paste from a normal hot card.
# Idle delta on this card is ~4 °C (core 46.0 / hotspot 50.0, 2026-08-04); memory
# junction idles ~12 °C ABOVE core and is what actually throttles a 575 W card.
#
# Core, memory and hotspot come from nvidia-gpu-sensors, NOT nvidia-smi:
# NVIDIA removed memory-junction and hotspot from the public query surface on the
# 50-series, so `nvidia-smi --query-gpu=temperature.memory` returns N/A while the
# sensors are perfectly readable through the driver's own ioctl interface.
#
# Needs root — the RM register allowlist excludes NV_THERM for non-root callers,
# so hotspot reads n/a without it.
#
# Usage:
#   sudo ./tools/gpu-thermal.sh stock                  # GPU alone, before undervolt
#   sudo ./tools/gpu-thermal.sh combined -c            # GPU **and** CPU together
#   sudo ./tools/gpu-thermal.sh uv-450w                # after an undervolt
#   sudo ./tools/gpu-thermal.sh stock -t 900           # longer load (default 600s)
#   sudo ./tools/gpu-thermal.sh stock -l "furmark ..." # different load command
#
# -c is the realistic worst case and the only one that shows the two chips
# INTERACTING: the GPU dumps its heat into the same case air the AIO radiator
# breathes, so CPU temps under a combined load can exceed a CPU-only run at
# identical CPU power. Run `stock` and `combined` back to back and diff them —
# the difference is the coupling, which neither test alone can show.
#
# Compare:  diff ~/bench/gpu-stock/summary.txt ~/bench/gpu-combined/summary.txt
#
# Requires: a GPU load tool. Default is gpu_burn — `yay -S gpu-burn-git`.

set -uo pipefail

# awk emits "68.6" while bash printf expects "68,6" under this machine's
# LC_NUMERIC=de_DE; pin C so the two agree (see global CLAUDE.md binding).
export LC_ALL=C

SECS=600
IDLE=30
LOAD=""
CPULOAD=0        # -c : load the CPU at the same time (the realistic worst case)

usage() { sed -n '2,28p' "$0"; exit "${1:-0}"; }

[ $# -ge 1 ] || usage 1
LABEL=$1; shift
case "$LABEL" in -h|--help) usage 0 ;; -*) echo "first arg must be a label" >&2; usage 1 ;; esac

while getopts ":t:i:l:ch" opt; do
  case "$opt" in
    t) SECS=$OPTARG ;;
    i) IDLE=$OPTARG ;;
    l) LOAD=$OPTARG ;;
    c) CPULOAD=1 ;;
    h) usage 0 ;;
    *) echo "unknown option -$OPTARG" >&2; usage 1 ;;
  esac
done

if [ "$CPULOAD" = 1 ]; then
  command -v stress-ng >/dev/null || { echo "-c needs stress-ng (sudo pacman -S stress-ng)" >&2; exit 1; }
fi

[ "$(id -u)" -eq 0 ] || { echo "needs root (hotspot is root-only); re-run with sudo" >&2; exit 1; }

SENSORS=~/dev/vendor/nvidia-gpu-sensors/build/nvidia-gpu-sensors
home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
[ -x "$SENSORS" ] || SENSORS="${home}/dev/vendor/nvidia-gpu-sensors/build/nvidia-gpu-sensors"
[ -x "$SENSORS" ] || { echo "missing: nvidia-gpu-sensors at $SENSORS" >&2
                       echo "  build it: see docs/cachyos/todo.md (GPU hotspot item)" >&2; exit 1; }
command -v nvidia-smi >/dev/null || { echo "missing: nvidia-smi" >&2; exit 1; }

if [ -z "$LOAD" ]; then
  for c in gpu_burn gpu-burn; do command -v $c >/dev/null && { LOAD="$c $SECS"; break; }; done
fi
[ -n "$LOAD" ] || { echo "no GPU load tool found." >&2
                    echo "  install: yay -S gpu-burn-git      (then re-run)" >&2
                    echo "  or pass one: -l 'furmark --...'" >&2; exit 1; }

OUT="${home:-/root}/bench/gpu-$LABEL"
mkdir -p "$OUT" || { echo "cannot create $OUT" >&2; exit 1; }

# --- sampling -----------------------------------------------------------------
# nvidia-gpu-sensors prints a fixed table; the GPU row starts with the index.
# Slots are core/mem/hotspot/NVVDD/MSVDD, each either "<value> <unit>" or "n/a",
# so walk the fields rather than assuming column positions — an n/a shifts them.
read_sensors() {
  "$SENSORS" 2>/dev/null | awk '
    $1=="0" { n=0; i=2
      while (i<=NF) {
        if ($i=="n/a") { v[n++]="n/a"; i++ } else { v[n++]=$i; i+=2 }
      }
      printf "%s %s %s %s %s", v[0],v[1],v[2],v[3],v[4]
    }'
}

# nvidia-smi's fan.speed covers the GPU's OWN fans only — it cannot see the case
# or AIO fans. Those live on the motherboard's nct6799 and matter here: a 575 W
# load heats the case, so chassis fans are part of how loud a GPU test gets.
# fan1 = Arctic P12 case fans, whose header reports 2 tach pulses/rev, so the raw
# value is halved; fan2 = Silent Wings 4 on the AIO radiator, correct as reported.
# (Channel map: fan-control/coolercontrol-labels.md.)
MB="" ; CPUHW=""
for h in /sys/class/hwmon/hwmon*; do
  case "$(cat "$h/name" 2>/dev/null)" in
    nct6799) MB="$h" ;;
    k10temp) CPUHW="$h" ;;
  esac
done

# CPU temps are sampled even for a GPU-only run: "the CPU was idle" is part of
# what makes a GPU-only baseline comparable to a combined one.
sample_once() {
  local s smi case_rpm=n/a aio_rpm=n/a tctl=n/a ccd1=n/a ccd2=n/a
  s=$(read_sensors)
  smi=$(nvidia-smi --query-gpu=fan.speed,power.draw,clocks.sm,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' ' ')
  if [ -n "$MB" ]; then
    case_rpm=$(( $(cat "$MB/fan1_input" 2>/dev/null || echo 0) / 2 ))
    aio_rpm=$(cat "$MB/fan2_input" 2>/dev/null || echo 0)
  fi
  if [ -n "$CPUHW" ]; then
    tctl=$(awk '{printf "%.1f", $1/1000}' "$CPUHW/temp1_input" 2>/dev/null || echo n/a)
    ccd1=$(awk '{printf "%.1f", $1/1000}' "$CPUHW/temp3_input" 2>/dev/null || echo n/a)
    ccd2=$(awk '{printf "%.1f", $1/1000}' "$CPUHW/temp4_input" 2>/dev/null || echo n/a)
  fi
  echo "$(date +%s) ${s:-n/a n/a n/a n/a n/a} ${smi:-n/a n/a n/a n/a} $case_rpm $aio_rpm $tctl $ccd1 $ccd2"
}

sampler() { while :; do sample_once; sleep 2; done > "$1"; }

# max of column $1 over file $2, ignoring n/a.
# `seen` is not decoration: testing the max itself would print n/a for a real
# ZERO, and a stopped GPU fan reads exactly 0 — that is data, not absence.
colmax() {
  awk -v c="$1" '$c!="n/a" { v=$c+0; if (!seen || v>m) { m=v; seen=1 } }
                 END{ if (seen) printf "%.1f", m; else print "n/a" }' "$2"
}
# largest (hotspot - core) seen in any single sample: cols 4 and 2
maxdelta() {
  awk '$2!="n/a" && $4!="n/a" { d=$4-$2; if (!seen || d>m) { m=d; seen=1 } }
       END{ if (seen) printf "%.1f", m; else print "n/a" }' "$1"
}

report() {   # $1=phase label  $2=file
  printf '  %-5s core %s  mem %s  hotspot %s  Δhot-core %s °C\n' \
    "$1" "$(colmax 2 "$2")" "$(colmax 3 "$2")" "$(colmax 4 "$2")" "$(maxdelta "$2")"
  printf '        %s W  %s MHz   CPU Tctl %s  CCD1 %s  CCD2 %s\n' \
    "$(colmax 8 "$2")" "$(colmax 9 "$2")" \
    "$(colmax 13 "$2")" "$(colmax 14 "$2")" "$(colmax 15 "$2")"
  printf '        fans: GPU %s%%  case %s rpm  AIO %s rpm\n' \
    "$(colmax 7 "$2")" "$(colmax 11 "$2")" "$(colmax 12 "$2")"
}

cat <<EOF
=== GPU thermal test: $LABEL ===
sensors: $SENSORS
load:    $LOAD
timing:  ${IDLE}s idle baseline, then ${SECS}s load
output:  $OUT

Idle reference on this card (2026-08-04): core 46.0 / mem 58.0 / hotspot 50.0,
i.e. hotspot-core = 4 °C. A disproportionate rise in that delta under load is
the die-contact signal; memory temp is what throttles.
EOF

{ echo "label:  $LABEL"; echo "date:   $(date -Is)"; echo "driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
  echo "gpu:    $(nvidia-smi --query-gpu=name --format=csv,noheader)"
  echo "load:   $LOAD"; echo "power-limit: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader)"
} > "$OUT/conditions.txt"

echo; echo "--- idle baseline (${IDLE}s) ---"
sampler "$OUT/idle.txt" & p=$!; sleep "$IDLE"; kill $p 2>/dev/null
report idle "$OUT/idle.txt"

echo; echo "--- LOAD: $LOAD ---"
[ "$CPULOAD" = 1 ] && echo "    + CPU all-core at the same time (combined worst case)"
echo "    (first 2-3 min are not steady state; watch the delta settle)"
sampler "$OUT/load.txt" & p=$!
cpid=""
if [ "$CPULOAD" = 1 ]; then
  # Slightly longer than the GPU load so the CPU never drops out first and
  # leaves the tail of the run measuring a GPU-only case under a combined label.
  stress-ng --matrix 0 -t $(( SECS + 30 )) >/dev/null 2>&1 &
  cpid=$!
fi
sh -c "$LOAD" >"$OUT/load-tool.log" 2>&1 &
lp=$!
while kill -0 $lp 2>/dev/null; do
  sleep 30
  printf '\r    t+%-4ss  core %s  mem %s  hot %s  Δ %s  %sW    ' \
    "$(( $(date +%s) - $(head -1 "$OUT/load.txt" | cut -d' ' -f1) ))" \
    "$(tail -1 "$OUT/load.txt" | cut -d' ' -f2)" "$(tail -1 "$OUT/load.txt" | cut -d' ' -f3)" \
    "$(tail -1 "$OUT/load.txt" | cut -d' ' -f4)" "$(maxdelta "$OUT/load.txt")" \
    "$(tail -1 "$OUT/load.txt" | cut -d' ' -f8)"
done
wait $lp 2>/dev/null
[ -n "$cpid" ] && kill $cpid 2>/dev/null
kill $p 2>/dev/null; echo

{
  echo "=== $LABEL ==="
  report idle "$OUT/idle.txt"
  report load "$OUT/load.txt"
} | tee "$OUT/summary.txt"

chown -R "${SUDO_USER:-root}" "${home:-/root}/bench" 2>/dev/null

cat <<EOF

Per-sample data: $OUT/{idle,load}.txt
  columns: epoch core mem hotspot nvvdd msvdd gpufan% watts sm_mhz util% case_rpm aio_rpm
  gpufan% is the GPU's own fans (nvidia-smi); case/AIO come from the
  motherboard nct6799 — nvidia-smi cannot see those. case_rpm is halved,
  the header reports 2 tach pulses/rev.
Load tool output: $OUT/load-tool.log
Compare: diff $OUT/summary.txt ~/bench/gpu-<other>/summary.txt

No verified threshold exists for this card — the circulating figures
(hotspot delta under ~15 °C, GDDR7 limit ~105 °C) are community numbers.
Judge by change from your own idle delta, not by an absolute.
EOF
