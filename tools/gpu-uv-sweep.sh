#!/usr/bin/env bash
# gpu-uv-sweep.sh — find the RTX 5090's undervolt wall automatically.
#
# Applies increasing global V/F frequency offsets via nvcurve and tests each one,
# stopping at the first failure and reporting the last-good offset.
#
# WHY THIS IS SAFE TO RUN UNATTENDED: nvcurve offsets are RUNTIME-ONLY. Nothing is
# persisted, no systemd unit is installed, so if a step hard-hangs the machine a
# power-cycle returns it to stock. That is what makes an automated voltage sweep
# reasonable here, where it normally would not be.
#
# WHAT THIS FINDS — and what it does NOT:
#   FINDS: the HARD wall — compute errors (gpu_burn self-validates its arithmetic),
#          crashes, driver resets (Xid).
#   MISSES: the SOFT wall — subtle visual artifacts, and instability that only shows
#          up in real gameplay. Those need human eyes and a real game.
# So the result is an UPPER BOUND. The daily-driver setting belongs BELOW it.
#
# Usage (needs root — nvcurve writes require it):
#   sudo ./tools/gpu-uv-sweep.sh                    # +50 .. +400 in steps of 50
#   sudo ./tools/gpu-uv-sweep.sh --start 150 --max 500 --step 25
#   sudo ./tools/gpu-uv-sweep.sh --burn 300 --furmark 180    # longer per-step tests
#   sudo ./tools/gpu-uv-sweep.sh --reset            # undo everything, then exit
#
# Progress is flushed to $OUT/progress.log after every step, so if the machine
# hangs, the file still says how far it got — and the reboot has already undone it.
# Re-run with --start <last-good + step> to resume.

set -uo pipefail
export LC_ALL=C          # awk emits "68.6", bash printf expects "68,6" here

START=50; MAX=400; STEP=50; BURN=180; FUR=120; DO_RESET=0

usage() { sed -n '2,30p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --start) START=$2; shift 2 ;;
    --max) MAX=$2; shift 2 ;;
    --step) STEP=$2; shift 2 ;;
    --burn) BURN=$2; shift 2 ;;
    --furmark) FUR=$2; shift 2 ;;
    --reset) DO_RESET=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (nvcurve writes require it); re-run with sudo" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
NVCURVE="$home/.local/bin/nvcurve"
[ -x "$NVCURVE" ] || NVCURVE=$(command -v nvcurve) || true
[ -n "$NVCURVE" ] && [ -x "$NVCURVE" ] || { echo "missing: nvcurve (uv tool install nvcurve)" >&2; exit 1; }

reset_stock() { "$NVCURVE" write --reset >/dev/null 2>&1; }

if [ "$DO_RESET" = 1 ]; then
  reset_stock && echo "offsets reset to stock." && exit 0
fi

command -v gpu_burn >/dev/null || GB=$(command -v gpu-burn) || true
GB=${GB:-$(command -v gpu_burn 2>/dev/null)}
[ -n "${GB:-}" ] || { echo "missing: gpu_burn  (yay -S gpu-burn-git)" >&2; exit 1; }
command -v furmark >/dev/null || { echo "missing: furmark  (yay -S furmark)" >&2; exit 1; }

OUT="${home:-/root}/bench/uv-sweep-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "cannot create $OUT" >&2; exit 1; }
LOG="$OUT/progress.log"

# Flush every line to disk immediately: if the machine hangs mid-step, this file is
# the only record of how far it got.
say() { echo "$*" | tee -a "$LOG"; sync; }

sensors_line() {
  nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
    | tr -d ' ' | tr ',' ' '
}

xid_since() {   # $1 = boot-relative marker string already in the journal
  journalctl -b --since "$1" 2>/dev/null | grep -ci 'xid' || true
}

say "=== GPU undervolt sweep ==="
say "range:   +$START .. +$MAX MHz, step $STEP"
say "per step: gpu_burn ${BURN}s, furmark ${FUR}s"
say "output:  $OUT"
say "nvcurve: $NVCURVE"
say "NOTHING PERSISTS — a reboot returns the card to stock."
say ""

reset_stock
LAST_GOOD=0
FAILED_AT=""

for (( off=START; off<=MAX; off+=STEP )); do
  say "───────────────────────────────────────────────"
  say "TRYING +$off MHz   ($(date +%H:%M:%S))"
  mark=$(date '+%Y-%m-%d %H:%M:%S')

  if ! "$NVCURVE" write --global --delta "$off" >"$OUT/apply-$off.log" 2>&1; then
    say "  APPLY FAILED — driver refused the offset. Stopping."
    FAILED_AT=$off; break
  fi

  # 1. gpu_burn — the gate. Self-validates its arithmetic; catches SILENT errors
  #    that no visual check can see. SMs and VRAM only, not the graphics path.
  say "  [1/3] gpu_burn ${BURN}s ..."
  "$GB" "$BURN" >"$OUT/burn-$off.log" 2>&1
  if grep -qi 'FAULTY' "$OUT/burn-$off.log"; then
    say "  ✗ gpu_burn reported FAULTY — compute errors at +$off"
    FAILED_AT=$off; break
  fi
  if ! grep -qi 'GPU 0: OK' "$OUT/burn-$off.log"; then
    say "  ✗ gpu_burn did not report OK (crashed or aborted) at +$off"
    FAILED_AT=$off; break
  fi
  # gpu_burn also reports throughput per interval — correctness AND performance from
  # one tool, so the sweep needs no separate benchmark run. Take the median: the first
  # interval runs cold and reads high, and throughput sags as the card heats.
  gflops=$(grep -oE '\(([0-9]+) Gflop/s\)' "$OUT/burn-$off.log" | grep -oE '[0-9]+' \
           | sort -n | awk '{a[NR]=$1} END{if(NR) print a[int(NR/2)+0]; else print 0}')
  say "      gpu_burn OK   median ${gflops} GFLOP/s   $(sensors_line)"

  # 2. FurMark Vulkan — exercises shaders/ROPs/texture units, the blocks gpu_burn
  #    never touches. A crash is detectable here; artifacts are NOT (no eyes).
  say "  [2/3] furmark (vulkan) ${FUR}s ..."
  if ! furmark --demo furmark-vk --width 2560 --height 1440 --max-time "$FUR" \
        --no-score-box >"$OUT/furmark-$off.log" 2>&1; then
    say "  ✗ furmark exited non-zero at +$off"
    FAILED_AT=$off; break
  fi
  say "      furmark survived   $(sensors_line)"

  # 3. Xid — driver-level resets, the loudest failure signal available
  say "  [3/3] checking journal for Xid ..."
  if [ "$(xid_since "$mark")" -gt 0 ]; then
    journalctl -b --since "$mark" | grep -i xid > "$OUT/xid-$off.log"
    say "  ✗ Xid error(s) logged at +$off — see xid-$off.log"
    FAILED_AT=$off; break
  fi

  say "  ✓ +$off MHz PASSED   ${gflops} GFLOP/s   $(sensors_line)"
  printf '%s\tPASS\t%s\t%s\n' "$off" "$gflops" "$(sensors_line)" >> "$OUT/results.tsv"
  LAST_GOOD=$off
done

reset_stock
say ""
say "═══════════════════════════════════════════════"
if [ -n "$FAILED_AT" ]; then
  say "First failure at:  +$FAILED_AT MHz"
else
  say "No failure up to the tested maximum (+$MAX) — the wall is higher."
fi
say "Last good offset:  +$LAST_GOOD MHz"
if [ "$LAST_GOOD" -gt 0 ]; then
  say "RECOMMENDED daily setting:  +$(( LAST_GOOD - STEP )) MHz"
  say "  (one step BELOW last-good — margin for a hot day, a driver update, and aging;"
  say "   the last passing setting is the edge, not the target)"
fi
say ""
say "Offsets have been RESET to stock. Nothing is applied and nothing persists."
say ""
say "This sweep found the HARD wall only. Before trusting a setting, still do the"
say "two things a script cannot: WATCH furmark for visual artifacts, and play a real"
say "game for ~1 h. Then check:  journalctl -b | grep -i xid"
say ""
if [ -s "$OUT/results.tsv" ]; then
  say "Per-offset results (offset / GFLOP/s / clock / watts / temp):"
  column -t "$OUT/results.tsv" | tee -a "$LOG"
  say ""
  say "Read GFLOP/s against WATTS, not on its own: an undervolt should hold or improve"
  say "throughput at LOWER power. Rising throughput with rising power is an overclock —"
  say "legitimate, but it costs heat, and this card gives back ~2.5 MHz per degree C."
fi
say ""
say "Apply a chosen offset:   sudo $NVCURVE write --global --delta <n>"
say "Undo:                    sudo $NVCURVE write --reset   (or reboot)"
say "Full logs:               $OUT"
