#!/usr/bin/env bash
# thermal-sweep.sh — map CPU load level → temperature → FAN SPEED on the desktop.
#
# Why this exists: on the 9950X3D, Tctl does NOT peak at full load. It peaks in
# the partial-load band (measured 2026-08-04: 79.8 °C at 8 threads vs 71.4 °C at
# 32), because below the ECO power cap the boost algorithm holds near-maximum
# voltage and each added core piles on heat at that voltage. Ordinary desktop
# work lives in exactly that band, which is why the fans surge during light work
# and settle under a full render. A fan curve tuned against an all-core stress
# test is therefore tuned against the COOLEST heavy case.
#
# It announces each phase before running it, so what you HEAR can be matched to
# what is loaded, and it logs actual fan RPM so the correlation is measured
# rather than remembered.
#
# No root needed — stress-ng and the hwmon reads are all unprivileged.
#
# Usage:
#   ./tools/thermal-sweep.sh before-co        # baseline, e.g. before Curve Optimizer
#   ./tools/thermal-sweep.sh after-co         # then compare
#   ./tools/thermal-sweep.sh eco-off -t 120   # longer phases, closer to steady state
#   ./tools/thermal-sweep.sh quick -n "1 8 32"
#
# Compare two runs:
#   diff ~/bench/thermal-before-co/table.txt ~/bench/thermal-after-co/table.txt
#
# Requires: stress-ng  (sudo pacman -S stress-ng)

set -uo pipefail

# German locale makes printf/awk expect and emit "," as the decimal separator,
# which rejects the "." values our own awk produces. Force C for both.
export LC_ALL=C

SECS=90          # load duration per phase; 35 s is NOT thermal steady state
COOL=45          # cooldown between phases
THREADS="1 2 4 8 16 32"

usage() { sed -n '2,28p' "$0"; exit "${1:-0}"; }

[ $# -ge 1 ] || usage 1
LABEL=$1; shift
case "$LABEL" in -h|--help) usage 0 ;; -*) echo "first arg must be a label" >&2; usage 1 ;; esac

while getopts ":t:c:n:h" opt; do
  case "$opt" in
    t) SECS=$OPTARG ;;
    c) COOL=$OPTARG ;;
    n) THREADS=$OPTARG ;;
    h) usage 0 ;;
    *) echo "unknown option -$OPTARG" >&2; usage 1 ;;
  esac
done

command -v stress-ng >/dev/null || { echo "missing: stress-ng (sudo pacman -S stress-ng)" >&2; exit 1; }

# --- locate sensors -----------------------------------------------------------
find_hwmon() {   # $1 = driver name
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "$1" ] && { echo "$h"; return 0; }
  done
  return 1
}

CPU=$(find_hwmon k10temp)  || { echo "no k10temp hwmon — cannot read CPU temps" >&2; exit 1; }
MB=$(find_hwmon nct6799)   || { echo "WARNING: no nct6799 — fan RPM will be unavailable" >&2; MB=""; }

# Channel map and the fan1 correction come from fan-control/coolercontrol-labels.md:
# fan1 = Arctic P12 case fans, header reports 2 tach pulses/rev so raw RPM is ~2x
# actual; fan2 = Silent Wings 4 on the AIO radiator, correct as reported;
# fan7 = AIO pump (roughly constant, not an acoustic variable).
FAN_CASE="$MB/fan1_input"   # divide by 2
FAN_AIO="$MB/fan2_input"

rd() { cat "$1" 2>/dev/null || echo 0; }

OUT=~/bench/thermal-$LABEL
# ~/bench can end up root-owned, because cpu-bench.sh runs under sudo and creates
# it as root. This script runs unprivileged, so that failure is silent and every
# later write dies one line at a time. Fail loudly here with the fix instead.
if ! mkdir -p "$OUT" 2>/dev/null; then
  echo "ERROR: cannot create $OUT" >&2
  echo "  ~/bench is probably root-owned (cpu-bench.sh runs under sudo)." >&2
  echo "  Fix:  sudo chown -R \"\$USER:\$USER\" ~/bench" >&2
  exit 1
fi

nphases=$(echo $THREADS | wc -w)
total=$(( nphases * (SECS + COOL) ))
cat <<EOF
=== thermal sweep: $LABEL ===
phases:    $THREADS threads
timing:    ${SECS}s load, ${COOL}s cooldown each
estimated: ~$(( total / 60 )) min $(( total % 60 ))s
output:    $OUT

Listen during each phase — the banner tells you what is loaded.
EOF

{
  echo "label:      $LABEL"
  echo "date:       $(date -Is)"
  echo "kernel:     $(uname -r)"
  echo "governor:   $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  echo "epp:        $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
  echo "power-mode: $(powerprofilesctl get 2>/dev/null || echo n/a)"
  echo "ram-speed:  $(awk '/MHz/{print $NF; exit}' /proc/cpuinfo >/dev/null; echo see-cpu-bench)"
  echo "phases:     $THREADS  (${SECS}s load / ${COOL}s cool)"
} > "$OUT/conditions.txt"

# --- sampling -----------------------------------------------------------------
# One sample line per second: tctl ccd1 ccd2 fan_case fan_aio  (milli-C and RPM)
sampler() {
  local out=$1
  while :; do
    printf '%s %s %s %s %s\n' \
      "$(rd $CPU/temp1_input)" "$(rd $CPU/temp3_input)" "$(rd $CPU/temp4_input)" \
      "$([ -n "$MB" ] && rd "$FAN_CASE" || echo 0)" \
      "$([ -n "$MB" ] && rd "$FAN_AIO"  || echo 0)"
    sleep 1
  done > "$out"
}

# peak of column $1 (1-indexed) in file $2, scaled by $3.
# `seen` rather than testing the max: a genuine ZERO is data — a stopped fan
# reads 0 rpm — and testing the value would report it as missing.
peak() {
  awk -v c="$1" -v s="$3" '{ v=$c+0; if (!seen || v>m) { m=v; seen=1 } }
                           END{ if (seen) printf "%.1f", m/s; else print "-" }' "$2"
}

# Integer maths only — no bc, no %f. Both were locale traps.
now_line() {   # live one-liner while a phase runs
  local t=$(( $(rd $CPU/temp1_input) / 1000 ))
  local fc=0 fa=0
  [ -n "$MB" ] && { fc=$(( $(rd "$FAN_CASE") / 2 )); fa=$(rd "$FAN_AIO"); }
  printf '\r    Tctl %3d °C   case %4d rpm   AIO %4d rpm    ' "$t" "$fc" "$fa"
}

printf 'threads\tTctl\tTccd1\tTccd2\tcase_rpm\tAIO_rpm\n' > "$OUT/table.txt"

for n in $THREADS; do
  echo
  echo "──────────────────────────────────────────────────────────"
  echo "  COOLING DOWN ${COOL}s — fans should settle to idle"
  echo "──────────────────────────────────────────────────────────"
  sleep "$COOL"

  echo
  echo "══════════════════════════════════════════════════════════"
  printf '  NOW RUNNING: %s THREAD(S) at full load for %ss\n' "$n" "$SECS"
  echo "══════════════════════════════════════════════════════════"

  sf="$OUT/n${n}.txt"
  sampler "$sf" & spid=$!
  stress-ng --cpu "$n" --cpu-method fft -t "$SECS" >/dev/null 2>&1 &
  spng=$!
  while kill -0 $spng 2>/dev/null; do now_line; sleep 3; done
  wait $spng 2>/dev/null
  kill $spid 2>/dev/null
  echo

  t=$(peak 1 "$sf" 1000); c1=$(peak 2 "$sf" 1000); c2=$(peak 3 "$sf" 1000)
  fc=$(peak 4 "$sf" 2);   fa=$(peak 5 "$sf" 1)
  printf '  PEAK: Tctl %s °C   Tccd1 %s   Tccd2 %s   case %s rpm   AIO %s rpm\n' \
    "$t" "$c1" "$c2" "$fc" "$fa"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$t" "$c1" "$c2" "$fc" "$fa" >> "$OUT/table.txt"
done

echo
echo "=== $LABEL — peaks per phase ==="
column -t "$OUT/table.txt"
cat <<EOF

Raw per-second samples: $OUT/n<threads>.txt
Compare with another run:
  diff $OUT/table.txt ~/bench/thermal-<other>/table.txt

Note: case_rpm is fan1 halved — the header reports 2 tach pulses/rev
(fan-control/coolercontrol-labels.md). AIO_rpm is reported as-is.
EOF
