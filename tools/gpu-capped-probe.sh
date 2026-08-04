#!/usr/bin/env bash
# gpu-capped-probe.sh — measure a setting in the POWER-CAPPED regime: stock vs setting,
# back to back, one command.
#
# WHY THIS EXISTS AS ITS OWN TOOL. An undervolt pays out in two different currencies,
# and which one you get depends entirely on whether the card is hitting its power limit:
#
#   COASTING (GravityMark, most games)  — the card is already as fast as its voltage
#     allows and is nowhere near the cap. A lower anchor buys LESS POWER at the same
#     speed. This is what gpu-uv-explore.sh measures, and what every stop rule reads.
#   CAPPED (FurMark, heavy 4K titles)   — the card is pinned at the power limit and the
#     limit is what is holding the clock down. Less voltage per MHz lets it clock UP
#     inside the same budget. The gain appears as MORE CLOCK at identical wattage.
#
# The explorer has always known this and has a probe for it — but that probe only fires
# after a completed 12-pass confirmation, at the end of a multi-hour sweep. On this
# machine that branch executed ZERO times across a full day of laddering, so the capped
# half of the answer was never once measured while the coasting half was measured six
# times. A comparison gated behind an hour of unrelated work is a comparison that does
# not happen. This runs it in four minutes.
#
# It is also the tool that stops the measurement being done by hand. The manual version
# is three commands — flatten, furmark, reset — and every hand-run of it discards the
# resolution and FPS, forgets the starting temperature, and produces two numbers nobody
# writes down. That is how a real 470->450 FPS observation became unanswerable here.
#
# Usage (root — applying the curve edit needs it; FurMark is dropped to the caller):
#   sudo ./tools/gpu-capped-probe.sh --mv 1000 --mhz 3000
#   sudo ./tools/gpu-capped-probe.sh --mv 1000 --mhz 3000 --seconds 180
#   sudo ./tools/gpu-capped-probe.sh --mv 1000 --mhz 3000 --stock-only
#
# The curve is reset to stock on ANY exit, including Ctrl-C and a crash.

set -uo pipefail
export LC_ALL=C

MV=0; MHZ=0; SECS=120; STOCK_ONLY=0; WIDTH=2560; HEIGHT=1440
SETTLE_C=50         # start each run at or below this; the second run matches the first
SETTLE_MAX=420      # seconds to wait for it before giving up and saying so

usage() { sed -n '2,31p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mv) MV=$2; shift 2 ;;
    --mhz) MHZ=$2; shift 2 ;;
    --seconds) SECS=$2; shift 2 ;;
    --width) WIDTH=$2; shift 2 ;;
    --height) HEIGHT=$2; shift 2 ;;
    --stock-only) STOCK_ONLY=1; shift ;;
    --settle) SETTLE_C=$2; shift 2 ;;
    --settle-max) SETTLE_MAX=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (applies curve edits); re-run with sudo" >&2; exit 1; }
command -v furmark >/dev/null || { echo "furmark not found  (yay -S furmark)" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
HERE="$(cd "$(dirname "$0")" && pwd)"
FLATTEN="$HERE/gpu-flatten.sh"
NVCURVE="${NVCURVE:-$home/.local/bin/nvcurve}"
[ -x "$FLATTEN" ] || { echo "gpu-flatten.sh missing" >&2; exit 1; }

OUT="$home/bench/capped-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/capped.log"
say() { echo "$*" | tee -a "$LOG"; sync; }

# Reset on ANY exit. A probe that leaves a curve edit applied after Ctrl-C is worse than
# no probe: the next thing measured is silently on a modified card.
cleanup() { "$NVCURVE" write --reset >/dev/null 2>&1; }
trap cleanup EXIT INT TERM

AS_USER=()
if [ -n "${SUDO_USER:-}" ]; then
  AS_USER=( sudo -u "$SUDO_USER"
            DISPLAY="${DISPLAY:-:0}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
            XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")"
            XAUTHORITY="${XAUTHORITY:-$home/.Xauthority}" HOME="$home" )
fi

# One FurMark run plus a sensor trace. Returns via files; prints nothing itself.
probe() {   # $1 = label
  # SEPARATE STATEMENTS, NOT `local a=$1 b="...$a..."`. Bash expands every word of a
  # command BEFORE the builtin runs, so a later word referencing an earlier assignment on
  # the same `local` line sees the OLD value — unset here, which under `set -u` aborts the
  # script. gpu-ab-compare.sh has the identical construct and survived only because the
  # name it referenced happened to also exist as a global.
  local lbl=$1
  local out="$OUT/$lbl.furmark.txt"
  local sens="$OUT/$lbl.sensors.txt"
  local t0; t0=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
  ( for i in $(seq 1 $(( SECS / 3 + 6 )) ); do
      nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits \
        | tr -d ' ' | tr ',' ' '; sleep 3
    done > "$sens" ) &
  local sp=$!
  timeout -k 10 $(( SECS + 30 )) "${AS_USER[@]}" \
    furmark --demo furmark-vk --width "$WIDTH" --height "$HEIGHT" \
            --max-time "$SECS" --no-score-box >"$out" 2>&1
  local rc=$?
  kill $sp 2>/dev/null; wait $sp 2>/dev/null
  echo "$t0" > "$OUT/$lbl.starttemp"
  return $rc
}

# Pull the numbers back out. FurMark prints the resolution it ACTUALLY rendered, which is
# not necessarily the one requested — a window manager can resize the window, and FurMark
# renders to the window. Comparing FPS across two different render sizes is meaningless,
# so the size is carried through and checked rather than assumed.
readback() {   # $1 = label -> "res fpsavg frames clk W temp0 tempmax"
  local lbl=$1
  local res fps fr
  res=$(awk -F: '/resolution/{gsub(/ /,"",$2); print $2}' "$OUT/$lbl.furmark.txt" 2>/dev/null)
  fps=$(awk -F: '/FPS \(min\/avg\/max\)/{split($2,a,"/"); gsub(/ /,"",a[2]); print a[2]}' "$OUT/$lbl.furmark.txt" 2>/dev/null)
  fr=$(awk -F: '/frames/{gsub(/ /,"",$2); print $2}' "$OUT/$lbl.furmark.txt" 2>/dev/null)
  # Average only the LOADED samples. Idle samples at the head and tail would drag the
  # mean toward numbers the card never ran at under load.
  read -r clk w tmax < <(awk '$2+0>300 {n++; c+=$1; p+=$2; if($3+0>t)t=$3+0}
    END{if(n) printf "%.0f %.0f %.0f", c/n, p/n, t; else printf "0 0 0"}' "$OUT/$lbl.sensors.txt" 2>/dev/null)
  echo "${res:-?} ${fps:-0} ${fr:-0} ${clk:-0} ${w:-0} $(cat "$OUT/$lbl.starttemp" 2>/dev/null || echo 0) ${tmax:-0}"
}

say "=== power-capped regime probe ==="
say "load:    FurMark Vulkan, ${WIDTH}x${HEIGHT}, ${SECS}s per run"
say "setting: ${MV} mV / ${MHZ} MHz"
say "output:  $OUT"
say ""
say "This is the regime GravityMark never reaches. There the card coasts below its"
say "power limit, so an undervolt shows up as LESS POWER at the same speed. Here the"
say "card is pinned AT the limit, so the same undervolt shows up as MORE CLOCK at the"
say "same wattage. Same setting, two different payouts — this measures the second."
say ""

# WAIT FOR A MATCHED STARTING TEMPERATURE. At a fixed power cap the clock is whatever
# the budget buys, and a hotter card leaks more, so start temperature moves the result
# directly. Measured 2026-08-04: the second run started 34 C warmer than the first, which
# handicaps it — a confound large enough to swamp the effect being measured.
settle() {   # wait until the GPU is at or below $1 C, or $2 seconds elapse
  local target=$1 budget=$2 t waited=0
  t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
  [ "${t:-0}" -le "$target" ] && return 0
  say "  cooling to <=${target}C before the run (now ${t}C, up to ${budget}s) ..."
  while [ "$waited" -lt "$budget" ]; do
    sleep 10; waited=$((waited+10))
    t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
    [ "${t:-0}" -le "$target" ] && { say "  settled at ${t}C after ${waited}s"; return 0; }
  done
  say "  ⚠️ still ${t}C after ${budget}s — proceeding, the comparison carries a thermal bias"
  return 1
}

say "[1/2] stock ..."
"$NVCURVE" write --reset >/dev/null 2>&1
settle "$SETTLE_C" "$SETTLE_MAX"
probe stock || say "  (furmark exited non-zero — check $OUT/stock.furmark.txt)"
read -r s_res s_fps s_fr s_clk s_w s_t0 s_tmax < <(readback stock)
say "  rendered ${s_res}   FPS avg ${s_fps}   ${s_clk} MHz @ ${s_w} W   temp ${s_t0}->${s_tmax} C"

if [ "$STOCK_ONLY" = 1 ]; then
  say ""; say "stock-only requested — done."; exit 0
fi
[ "$MV" -gt 0 ] && [ "$MHZ" -gt 0 ] || { echo "need --mv and --mhz (or --stock-only)" >&2; exit 1; }

say ""
say "[2/2] ${MV} mV / ${MHZ} MHz ..."
# Match the FIRST run's actual starting temperature, not a fixed target — that is the
# number the comparison has to hold constant.
settle "$(cat "$OUT/stock.starttemp" 2>/dev/null || echo "$SETTLE_C")" "$SETTLE_MAX"
"$FLATTEN" --mv "$MV" --mhz "$MHZ" >"$OUT/flatten.log" 2>&1 || {
  say "  FLATTEN REFUSED — see $OUT/flatten.log. Nothing was applied; stock result above stands."
  exit 1; }
probe setting || say "  (furmark exited non-zero — check $OUT/setting.furmark.txt)"
read -r c_res c_fps c_fr c_clk c_w c_t0 c_tmax < <(readback setting)
say "  rendered ${c_res}   FPS avg ${c_fps}   ${c_clk} MHz @ ${c_w} W   temp ${c_t0}->${c_tmax} C"
"$NVCURVE" write --reset >/dev/null 2>&1

say ""
say "═══════════════════════════════════════════════"
if [ "$s_res" != "$c_res" ]; then
  say "⚠️ RENDER SIZE DIFFERED between the two runs (${s_res} vs ${c_res})."
  say "   FPS is NOT comparable — different pixel counts. Clock and power still are."
fi
awk -v sc="$s_clk" -v sw="$s_w" -v sf="$s_fps" -v st="$s_t0" \
    -v cc="$c_clk" -v cw="$c_w" -v cf="$c_fps" -v ct="$c_t0" -v same="$([ "$s_res" = "$c_res" ] && echo 1 || echo 0)" '
BEGIN {
  printf "  %-10s %10s %10s %10s\n", "", "stock", "setting", "change"
  printf "  %-10s %10d %10d %+9.1f%%\n", "clock",  sc, cc, (cc/sc-1)*100
  printf "  %-10s %10d %10d %+9.1f%%\n", "watts",  sw, cw, (cw/sw-1)*100
  if (same && sf>0) printf "  %-10s %10d %10d %+9.1f%%\n", "FPS avg", sf, cf, (cf/sf-1)*100
  print ""
  # The cap is the precondition for the whole comparison. Without it this is not the
  # capped regime and the numbers answer a different question than the one asked.
  if (sw < 0.97*575 && sw < 0.97*cw) {
    print "  NOTE: stock did not reach the power cap, so this was not the capped regime."
    print "  The comparison below is not the one this tool is for."
  }
  # THE VERDICT READS FPS, NOT CLOCK. Reported clock is the number this whole project
  # has proven unreliable, and the capped regime is where it is worst: measured
  # 2026-08-04, stock reported 2508 MHz and delivered 445 FPS while the setting reported
  # 2200 MHz and delivered 457 FPS. FurMark is a fixed shader load, so a card genuinely
  # running 14% faster cannot produce FEWER frames. The stock reading is inflated — it is
  # stretching under the cap — and a clock-based verdict called that a loss.
  if (!same || sf<=0) {
    print "  ► Cannot judge: the two runs rendered at different sizes, so FPS is not"
    print "    comparable, and reported clock is not trustworthy enough to decide on."
  }
  else if (cf > sf*1.01 && cw >= sw*0.98)
    printf "  ► GAIN: %+.1f%% MORE WORK at the same power. This is the capped-regime\n    payout — the setting converts saved voltage into throughput, not watts.\n", (cf/sf-1)*100
  else if (cw < sw*0.97)
    printf "  ► The card did NOT stay pinned at the cap (%.0f W -> %.0f W), so the payout\n    came as less power, not more work. That is the coasting result.\n", sw, cw
  else if (cf < sf*0.99)
    printf "  ► SLOWER by %.1f%% at the same power — the setting costs throughput here.\n", (1-cf/sf)*100
  else
    print  "  ► No throughput change in the capped regime. The setting pays out as lower\n    power in coasting loads only — still the result that matters for most games."
  if (cc < sc*0.98 && cf > sf*1.01)
    printf "\n  NOTE: reported clock FELL %.1f%% while delivered work ROSE %.1f%%. A fixed\n    shader load cannot do that if both clocks were real — the higher reading is\n    the false one. Judge this regime on FPS only.\n", (1-cc/sc)*100, (cf/sf-1)*100
  if (st>0 && ct>0 && (ct-st) > 8)
    printf "\n  ⚠️ the second run started %d C warmer (%d -> %d). At a fixed power cap a hotter\n     card buys less clock, so this comparison is biased AGAINST the setting.\n", ct-st, st, ct
}'| tee -a "$LOG"

say ""
say "Curve reset to stock. Nothing persists across a reboot."
say "Full data: $OUT"
chown -R "${SUDO_USER:-root}" "$OUT" 2>/dev/null
