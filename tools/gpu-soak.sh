#!/usr/bin/env bash
# gpu-soak.sh — unattended GPU stability soak at GAMING clocks, with automatic
# hang detection. Replaces "play a game for an hour and hope you notice".
#
# WHY THIS EXISTS. The +400 MHz offset failure on 2026-08-04 taught three things:
#   1. It appeared ~2m40s into a run, not at startup — instability at the wall is
#      PROBABILISTIC. Short tests prove nothing. Duration is the test.
#   2. There was NO visual artifact. The failure was a hang (Xid 109, CTX SWITCH
#      TIMEOUT). So watching the screen was never going to catch it — which means
#      the test does not need a human, only a long enough load and a log reader.
#   3. gpu_burn passed it clean. It runs power-capped at ~2125 MHz while games run
#      ~3040 MHz, so it validates a V/F point that is never used. Only a load at
#      gaming clocks tests the regime that matters.
#
# GravityMark RT is the right load precisely because it is NOT power-hungry:
# measured 3.04 GHz at 386 W of a 575 W limit. High clock, low power — the card sits
# at its VOLTAGE ceiling, which is exactly where a curve offset destabilises it.
# A power-virus (gpu_burn, FurMark) pins 575 W and clocks DOWN, hiding the fault.
#
# Detection is fully automatic, two independent channels:
#   * kernel journal  -> NVRM Xid lines (the authoritative signal)
#   * GravityMark log -> "device lost" / VK errors (the application's own view)
#
# ⚠️ RUN THE STOCK CONTROL FIRST. A hang under an offset only implicates the offset if
# the machine is known stable WITHOUT it over the same duration. This machine has prior
# history of Xid 109 hangs (Marvel Rivals / descriptor_heap, docs/cachyos/gaming/games/
# marvel-rivals.md) — that cause was identified and fixed, but it means "Xid 109 appeared"
# is not by itself proof that the offset caused it. Establish the baseline, then test.
#
#   1. ./tools/gpu-soak.sh                       # CONTROL — stock, must pass
#   2. sudo ./tools/gpu-soak.sh --offset 250     # then the candidate
#
# Usage (no root needed unless --offset is given):
#   ./tools/gpu-soak.sh                          # 20 passes ~55 min at current settings
#   ./tools/gpu-soak.sh --passes 40              # ~110 min
#   sudo ./tools/gpu-soak.sh --offset 250        # apply offset, soak, restore on exit
#   ./tools/gpu-soak.sh --asteroids 500000       # heavier scene
#   ./tools/gpu-soak.sh --screen 1               # BEST: fullscreen on a second monitor,
#                                                # full load, primary display stays free
#   ./tools/gpu-soak.sh --windowed --width 1280 --height 720
#                                                # fallback on a single monitor
#
# KEEPING THE MACHINE USABLE. Two ways, and they are not equivalent:
#   --screen N  puts the FULLSCREEN load on another monitor. If that monitor matches the
#               primary's resolution (both 2560x1440 here) the load is IDENTICAL — this
#               costs nothing and is the right choice.
#   --windowed  shrinks the render target, which is a LIGHTER load. A setting surviving
#               1280x720 windowed is NOT proven at 2560x1440. Fallback only.
#
# Each GravityMark pass is ~167 s, so passes x 3 min is roughly the wall-clock time.

set -uo pipefail
export LC_ALL=C          # awk emits "68.6", bash printf expects "68,6" on this machine

PASSES=20
ASTEROIDS=200000
WIDTH=2560
HEIGHT=1440
OFFSET=""
FULLSCREEN=1     # --windowed drops this so the machine stays usable on one monitor
SCREEN=0         # --screen N puts the fullscreen load on a SECOND monitor

usage() { sed -n '2,32p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --passes) PASSES=$2; shift 2 ;;
    --asteroids) ASTEROIDS=$2; shift 2 ;;
    --width) WIDTH=$2; shift 2 ;;
    --height) HEIGHT=$2; shift 2 ;;
    --offset) OFFSET=$2; shift 2 ;;
    --windowed) FULLSCREEN=0; shift ;;
    --screen) SCREEN=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
GM="$home/Downloads/GravityMark_1.89_linux/bin/GravityMark.x64"
[ -x "$GM" ] || { echo "GravityMark not found at $GM" >&2
                  echo "  adjust the path in this script, or reinstall from gravitymark.tellusim.com" >&2; exit 1; }
NVCURVE="$home/.local/bin/nvcurve"

if [ -n "$OFFSET" ]; then
  [ "$(id -u)" -eq 0 ] || { echo "--offset needs root; re-run with sudo" >&2; exit 1; }
  [ -x "$NVCURVE" ] || { echo "nvcurve not found at $NVCURVE" >&2; exit 1; }
fi

OUT="${home:-/root}/bench/soak-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "cannot create $OUT" >&2; exit 1; }
LOG="$OUT/soak.log"
say() { echo "$*" | tee -a "$LOG"; sync; }   # sync: a hang must not lose the record

cleanup() {
  [ -n "${SPID:-}" ] && kill "$SPID" 2>/dev/null
  if [ -n "$OFFSET" ] && [ -x "$NVCURVE" ]; then
    echo; echo "restoring stock V/F offsets ..."
    "$NVCURVE" write --reset >/dev/null 2>&1
  fi
}
trap cleanup EXIT INT TERM

# --- sensors ------------------------------------------------------------------------
sampler() {
  while :; do
    printf '%s %s\n' "$(date +%s)" \
      "$(nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu,fan.speed,utilization.gpu \
         --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' ' ')"
    sleep 3
  done > "$1"
}
cmax()  { awk -v c="$1" '$c!="n/a"{v=$c+0; if(!s||v>m){m=v;s=1}} END{if(s) printf "%.0f", m; else print "n/a"}' "$2"; }
cmean() { awk -v c="$1" '$c!="n/a"{s+=$c;n++} END{if(n) printf "%.0f", s/n; else print "n/a"}' "$2"; }

START_MARK=$(date '+%Y-%m-%d %H:%M:%S')

say "=== GPU stability soak — gaming clocks, unattended ==="
say "passes:    $PASSES  (~$(( PASSES * 167 / 60 )) min)"
say "scene:     ${WIDTH}x${HEIGHT}, ${ASTEROIDS} asteroids, Vulkan RT$([ "$FULLSCREEN" = 0 ] && echo ' (WINDOWED — lighter load than fullscreen)')"
say "screen:    $SCREEN$([ "$SCREEN" != 0 ] && echo ' (secondary — primary display stays usable)')"
say "offset:    ${OFFSET:-<current, unchanged>}"
say "output:    $OUT"
say ""
say "Detects HANGS (Xid / device lost), which is how an unstable undervolt actually"
say "fails — the 2026-08-04 +400 failure produced no visual artifact at all. Runs at"
say "~3.0 GHz and ~390 W: high clock, low power, the regime gpu_burn cannot reach."
say ""

if [ -n "$OFFSET" ]; then
  "$NVCURVE" write --global --delta "$OFFSET" >"$OUT/offset.log" 2>&1 \
    && say "applied V/F offset +${OFFSET} MHz" \
    || { say "FAILED to apply offset — aborting"; exit 1; }
  say ""
fi

sampler "$OUT/sensors.txt" & SPID=$!

if [ "$SCREEN" = 0 ] && [ "$FULLSCREEN" = 1 ]; then
  say "starting $PASSES passes at $(date +%H:%M:%S) — this will take over your display."
  say "  (a second monitor? use --screen 1 and keep working)"
else
  say "starting $PASSES passes at $(date +%H:%M:%S) ..."
fi
say ""

# -count N runs N benchmark passes back to back; -close 1 exits when done.
# -times logs per-frame timings, so a stutter/hitch is recoverable after the fact.
# MUST run from bin/ — the vendor's own run_*.sh scripts cd there first, because
# libTellusim_x64.so sits beside the binary and is found via an empty rpath. Invoking
# it by absolute path from anywhere else dies with "cannot open shared object file"
# and exit 127, which is a LAUNCH failure and must never be read as instability.
# ONE INVOCATION PER PASS, not -count N. Three reasons, all learned the hard way:
#   1. With -count N, GravityMark prints "Benchmark loop" per pass but only ONE "Score:"
#      at the very end — so a pass counter keyed on Score reports 0 and calls a clean
#      run FAILED. Observed on the 2026-08-04 stock baseline: 7 passes done, 0 counted.
#   2. Per-pass scores are the only way to measure run-to-run VARIANCE, without which
#      "the offset gained 3%" cannot be separated from noise.
#   3. A hang at pass 19 loses every earlier score, because nothing reaches disk until
#      the process exits. One invocation per pass makes each result durable.
#
# Hard timeout per pass: a wedged benchmark must not stall an unattended run.
PASS_BUDGET=$(( 167 * 150 / 100 + 90 ))
say "per-pass hard timeout: ${PASS_BUDGET}s"

GM_ARGS=( -vk -raytracing 1 -temporal 1 -fullscreen "$FULLSCREEN" -screen "$SCREEN"
          -benchmark 1 -count 1 -close 1
          -asteroids "$ASTEROIDS" -width "$WIDTH" -height "$HEIGHT" )

# Root would give the benchmark HOME=/root and no display authority; only nvcurve
# needs root. Drop to the invoking user, carrying the session environment across.
AS_USER=()
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  say "benchmark runs as $SUDO_USER (root has the wrong HOME and no display access)"
  AS_USER=( sudo -u "$SUDO_USER"
            DISPLAY="${DISPLAY:-:0}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
            XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")"
            XAUTHORITY="${XAUTHORITY:-$home/.Xauthority}" HOME="$home" )
fi
say ""

: > "$OUT/scores.txt"
GM_RC=0
NRUNS=0
for i in $(seq 1 "$PASSES"); do
  plog="$OUT/pass-$(printf '%02d' "$i").log"
  ( cd "$(dirname "$GM")" && timeout -k 20 "$PASS_BUDGET" "${AS_USER[@]}" \
      ./"$(basename "$GM")" "${GM_ARGS[@]}" ) >"$plog" 2>&1
  rc=$?
  sc=$(grep -oE 'Score: [0-9]+' "$plog" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  cat "$plog" >> "$OUT/gravitymark.log"
  if [ "$rc" -ne 0 ] || [ -z "$sc" ]; then
    say "  pass $i/$PASSES: FAILED  rc=$rc  score=${sc:-none}"
    GM_RC=$rc; [ "$GM_RC" -eq 0 ] && GM_RC=1
    break
  fi
  echo "$sc" >> "$OUT/scores.txt"; sync
  NRUNS=$((NRUNS+1))
  say "  pass $i/$PASSES: $sc   $(nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' ' ')"
done
chown -R "${SUDO_USER:-$USER}" "$OUT" 2>/dev/null
chown -R "${SUDO_USER:-$USER}" "$OUT" 2>/dev/null

kill "$SPID" 2>/dev/null

# --- verdict: two independent detectors ---------------------------------------------
say ""
say "═══════════════════════════════════════════════"
XID=$(journalctl -k --since "$START_MARK" 2>/dev/null | grep -i 'xid' | tee "$OUT/xid.log" | wc -l)
# `grep -c` prints 0 AND exits 1 on no match, so a `|| echo 0` fallback would append a
# SECOND zero and break the numeric test below. grep -c always prints a number: use it.
DEVLOST=$(grep -ci 'device lost\|VK::error' "$OUT/gravitymark.log" 2>/dev/null)
DEVLOST=${DEVLOST:-0}
SCORES=$(tr '\n' ' ' < "$OUT/scores.txt" 2>/dev/null)

say "passes completed:   $NRUNS of $PASSES"
say "GravityMark exit:   $GM_RC"
say "Xid entries:        $XID"
say "VK device-lost:     $DEVLOST"
say ""
say "sensors — peak clock $(cmax 2 "$OUT/sensors.txt") MHz   mean $(cmean 2 "$OUT/sensors.txt") MHz"
say "          peak power $(cmax 3 "$OUT/sensors.txt") W     mean $(cmean 3 "$OUT/sensors.txt") W"
say "          peak temp  $(cmax 4 "$OUT/sensors.txt") C     peak fan $(cmax 5 "$OUT/sensors.txt") %"
say ""
if [ -n "$SCORES" ]; then
  say "scores: $SCORES"
  echo "$SCORES" | tr ' ' '\n' | grep -E '^[0-9]+$' | awk '
    {s+=$1; n++; if(!mn||$1<mn)mn=$1; if($1>mx)mx=$1}
    END{ if(n) printf "  mean %.0f   min %d   max %d   spread %.1f%%\n", s/n, mn, mx, (mx-mn)*100/(s/n) }' | tee -a "$LOG"
  say "  (spread is your run-to-run variance — an offset gain smaller than this is noise)"
fi
say ""

# DID THE TEST EVEN RUN? A benchmark that never started is not an unstable GPU. Getting
# this wrong once already produced "the machine is unstable at factory settings" from a
# missing shared library — a false alarm that would train anyone to discount a real one.
# Exit 127 = command/library not found; a log with a loader error; or zero passes AND
# zero Xid AND zero device-lost, which is the signature of "nothing happened".
if [ "$GM_RC" -eq 127 ] \
   || grep -qi 'error while loading shared libraries\|command not found' "$OUT/gravitymark.log" 2>/dev/null \
   || { [ "$NRUNS" -eq 0 ] && [ "$XID" -eq 0 ] && [ "$DEVLOST" -eq 0 ]; }; then
  say "⚠️ INCONCLUSIVE — the benchmark never ran. This says NOTHING about stability."
  say ""
  say "   GravityMark exit $GM_RC, $NRUNS passes, no Xid, no device-lost."
  say "   First lines of its output:"
  head -3 "$OUT/gravitymark.log" 2>/dev/null | sed 's/^/     /' | tee -a "$LOG"
  say ""
  say "   Fix the launch problem and re-run. Nothing about the GPU is in question here."
  exit 2
fi

if [ "$GM_RC" -eq 124 ] || [ "$GM_RC" -eq 137 ]; then
  say "❌ FAILED — the benchmark WEDGED and hit the ${PASS_BUDGET}s per-pass hard timeout."
  say "   It stopped responding without exiting. That is a hang, and it counts as a"
  say "   failure at this setting — completed $NRUNS of $PASSES passes before stalling."
  [ "$XID" -gt 0 ] && { say "   Xid detail:"; tail -5 "$OUT/xid.log" | sed 's/^/     /' | tee -a "$LOG"; }
  exit 1
fi

if [ "$XID" -gt 0 ] || [ "$DEVLOST" -gt 0 ] || [ "$NRUNS" -lt "$PASSES" ]; then
  say "❌ FAILED — unstable at this setting."
  if [ -z "$OFFSET" ]; then
    say "   ⚠️ This was a STOCK run. The fault is NOT an undervolt — the machine is"
    say "      unstable at factory settings, and that is a different investigation."
    say "      See docs/cachyos/issues/known-issues.md and the parked freeze item."
  else
    say "   Attribute to the offset ONLY if a stock control soak of the same length"
    say "   passed. Without that control this is a hang, not a verdict on +$OFFSET."
  fi
  [ "$XID" -gt 0 ] && { say "   Xid detail:"; sed 's/^/     /' "$OUT/xid.log" | tail -5 | tee -a "$LOG"; }
  [ "$DEVLOST" -gt 0 ] && say "   GravityMark reported device-lost / VK errors (see gravitymark.log)"
  [ "$NRUNS" -lt "$PASSES" ] && say "   only $NRUNS of $PASSES passes completed — it died mid-soak"
  say ""
  say "Back off one step and re-soak. Recover now with:"
  say "   sudo $NVCURVE write --reset      (or reboot — nothing persists)"
  exit 1
fi

say "✅ PASSED — $PASSES passes, no Xid, no device-lost."
say ""
say "⚠️ This proves the HANG path only. It cannot see visual artifacts, and the scene"
say "   is fixed — a real game varies shaders, resolution and load in ways this does"
say "   not. It is a much better screen than a 3-minute benchmark, not a substitute"
say "   for eventually playing something."
say ""
say "Live Xid watching during any future session:  ./tools/gpu-hang-watch.sh"
say "Full logs: $OUT"
