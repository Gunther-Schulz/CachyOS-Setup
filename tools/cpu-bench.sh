#!/usr/bin/env bash
# cpu-bench.sh — before/after CPU benchmark for the 9950X3D ECO + Curve Optimizer work.
#
# Runs the battery from docs/cachyos/todo.md three times each and reports medians,
# with turbostat logging power/clocks/temps DURING the load. Records the machine
# conditions alongside the numbers, because a before/after comparison is only
# valid if the conditions match — and that is the part people forget.
#
# Usage (needs root for turbostat's MSR access):
#   sudo ./tools/cpu-bench.sh stock          # BEFORE any BIOS change
#   sudo ./tools/cpu-bench.sh eco            # after ECO alone
#   sudo ./tools/cpu-bench.sh eco-co         # after ECO + Curve Optimizer
#
#   sudo ./tools/cpu-bench.sh stock -n 5     # more runs (default 3)
#   sudo ./tools/cpu-bench.sh stock -t 120   # longer runs (default 60s)
#
# Results land in ~/bench/<label>/ : raw stress-ng output, raw turbostat logs,
# conditions.txt, and summary.txt. Compare two labels with:
#   diff ~/bench/stock/conditions.txt ~/bench/eco/conditions.txt
#
# Requires: stress-ng turbostat  (sudo pacman -S stress-ng turbostat)

set -uo pipefail

RUNS=3
SECS=60
LABEL=""

usage() { sed -n '2,25p' "$0"; exit "${1:-0}"; }

[ $# -ge 1 ] || usage 1
LABEL=$1; shift
case "$LABEL" in -h|--help) usage 0 ;; -*) echo "first arg must be a label" >&2; usage 1 ;; esac

while getopts ":n:t:h" opt; do
  case "$opt" in
    n) RUNS=$OPTARG ;;
    t) SECS=$OPTARG ;;
    h) usage 0 ;;
    *) echo "unknown option -$OPTARG" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (turbostat reads MSRs); re-run with sudo" >&2; exit 1; }
for b in stress-ng turbostat; do
  command -v $b >/dev/null || { echo "missing: $b  (sudo pacman -S stress-ng turbostat)" >&2; exit 1; }
done

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
OUT="${home:-/root}/bench/$LABEL"
mkdir -p "$OUT"

# --- conditions: the comparability record -------------------------------------
cond="$OUT/conditions.txt"
{
  echo "label:        $LABEL"
  echo "date:         $(date -Is)"
  echo "kernel:       $(uname -r)"
  echo "cpu:          $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
  echo "threads:      $(nproc)"
  echo "governor:     $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  echo "epp:          $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
  echo "driver:       $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null)"
  echo "power-mode:   $(sudo -u "${SUDO_USER:-root}" powerprofilesctl get 2>/dev/null || echo n/a)"
  echo "ram-speed:    $(dmidecode -t memory 2>/dev/null | awk '/Configured Memory Speed/{print $4" "$5; exit}')"
  echo "ram-total:    $(free -g | awk '/^Mem:/{print $2" GiB"}')"
  echo "runs:         $RUNS x ${SECS}s"
  echo "loadavg-pre:  $(cut -d' ' -f1-3 /proc/loadavg)"
} > "$cond"

echo "=== conditions ==="; cat "$cond"; echo

# A busy machine invalidates the numbers; say so rather than silently skewing them.
load1=$(cut -d' ' -f1 /proc/loadavg)
if awk "BEGIN{exit !($load1 > 1.5)}"; then
  echo "WARNING: loadavg is $load1 — close background work or the medians will be noisy."
  echo "Continuing in 10s (Ctrl-C to abort)..."; sleep 10
fi

# --- helpers ------------------------------------------------------------------
# stress-ng --metrics-brief prints the stressor row; column 9 is bogo ops/s (real time).
bogo_from() { awk -v s="$1" '$0 ~ (" "s" ") && NF>=9 {for(i=1;i<=NF;i++) if($i==s){print $(i+5); exit}}' "$2"; }
# Temperature does NOT come from turbostat: both CoreTmp and PkgTmp were asked
# for and neither produced a column on this AMD platform (verified 2026-08-04 —
# the -S header came back as just "Busy% Bzy_MHz PkgWatt"). k10temp via sysfs
# works and is strictly better here: it exposes Tctl (what the board's fan curve
# follows) plus per-CCD temps, and on a 9950X3D the two CCDs differ — CCD0 carries
# the 3D V-Cache and runs cooler than CCD1.
k10temp_dir() {
  local h n
  for h in /sys/class/hwmon/hwmon*; do
    n=$(cat "$h/name" 2>/dev/null) || continue
    [ "$n" = k10temp ] && { echo "$h"; return 0; }
  done
  return 1
}

# Sample k10temp every 2s into $1 until killed.
temp_sampler() {
  local out=$1 hw=$2 l
  while :; do
    for l in "$hw"/temp*_label; do
      printf '%s=%s ' "$(cat "$l")" "$(cat "${l%_label}_input")"
    done
    echo
    sleep 2
  done > "$out"
}

# Max of a named k10temp label across a sample file, in degrees C.
temp_max() {
  awk -v want="$1" '{for(i=1;i<=NF;i++){split($i,kv,"=");
                       if(kv[1]==want && kv[2]+0>m) m=kv[2]+0}}
                    END{if(m) printf "%.1f", m/1000; else print "n/a"}' "$2"
}

# turbostat -S prints a summary row per interval, but the file opens with an
# elapsed-time line ("60.014170 sec") BEFORE the header — so the header is not
# necessarily line 1. Find it wherever it is, and re-find it if it repeats.
col_avg() {
  awk -v want="$1" '
    { for(i=1;i<=NF;i++) if($i==want) { c=i; hdr=1; break } }
    hdr { hdr=0; next }
    c && $c ~ /^[0-9.]+$/ { s+=$c; n++ }
    END { if(n) printf "%.1f", s/n; else print "n/a" }' "$2"
}
median() { printf '%s\n' "$@" | sort -g | awk '{a[NR]=$1} END{if(NR%2) print a[(NR+1)/2]; else printf "%.2f", (a[NR/2]+a[NR/2+1])/2}'; }

run_set() {          # $1=name  $2=stressor-label  $3..=stress-ng args
  local name=$1 stressor=$2; shift 2
  local -a scores=() watts=() mhz=() temp=()
  echo "--- $name: $RUNS x ${SECS}s ---"
  for i in $(seq 1 "$RUNS"); do
    local so="$OUT/${name}-run${i}.txt" to="$OUT/${name}-run${i}-turbostat.txt"
    local tf="$OUT/${name}-run${i}-k10temp.txt" sampler=""
    if [ -n "$HWMON" ]; then
      temp_sampler "$tf" "$HWMON" & sampler=$!
    fi
    turbostat --interval 5 --quiet -S --show PkgWatt,Busy%,Bzy_MHz --out "$to" \
      -- stress-ng "$@" --metrics-brief -t "$SECS" > "$so" 2>&1
    [ -n "$sampler" ] && kill "$sampler" 2>/dev/null
    local b w f c
    b=$(bogo_from "$stressor" "$so"); w=$(col_avg PkgWatt "$to")
    f=$(col_avg Bzy_MHz "$to")
    c=$([ -s "$tf" ] && temp_max Tctl "$tf" || echo n/a)
    b=${b:-0}
    scores+=("$b"); watts+=("$w"); mhz+=("$f"); temp+=("$c")
    printf '  run %d: %s bogo-ops/s   %s W   %s MHz   Tctl max %s °C' "$i" "$b" "$w" "$f" "$c"
    if [ -s "$tf" ]; then
      printf '   (CCD1 %s / CCD2 %s)' "$(temp_max Tccd1 "$tf")" "$(temp_max Tccd2 "$tf")"
    fi
    echo
    sleep 15   # let temps settle between runs
  done
  local mb mw mf mc
  mb=$(median "${scores[@]}"); mw=$(median "${watts[@]}")
  mf=$(median "${mhz[@]}");    mc=$(median "${temp[@]}")
  printf '  MEDIAN: %s bogo-ops/s   %s W   %s MHz   Tctl max %s °C\n\n' "$mb" "$mw" "$mf" "$mc"
  printf '%s\tmedian_bogo_ops_s=%s\tmedian_pkg_watt=%s\tmedian_bzy_mhz=%s\tmedian_tctl_max=%s\truns=%s\n' \
    "$name" "$mb" "$mw" "$mf" "$mc" "$RUNS" >> "$OUT/summary.txt"
}

HWMON=$(k10temp_dir) || { echo "WARNING: no k10temp hwmon found — temperatures will read n/a"; HWMON=""; }

: > "$OUT/summary.txt"
run_set multicore matrix --matrix 0
run_set single-thread cpu --cpu 1 --cpu-method fft

{ echo; echo "loadavg-post: $(cut -d' ' -f1-3 /proc/loadavg)"; } >> "$cond"
chown -R "${SUDO_USER:-root}" "$OUT" 2>/dev/null

echo "=== summary ($LABEL) ==="
cat "$OUT/summary.txt"
echo
echo "Raw output + turbostat logs: $OUT"
echo "Compare later with:  diff $OUT/conditions.txt ~/bench/<other-label>/conditions.txt"
