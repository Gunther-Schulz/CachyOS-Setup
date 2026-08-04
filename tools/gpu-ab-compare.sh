#!/usr/bin/env bash
# gpu-ab-compare.sh — interleaved A/B test of one setting against stock, with paired
# statistics. The tool that decides whether a performance claim is real.
#
# WHY THIS EXISTS. Every rung in gpu-uv-explore.sh is a BLOCK: four passes at one
# setting, then four at the next. Blocks are compared across time, so any drift between
# them is charged to the setting. On 2026-08-04 that produced a claim and its own
# refutation from the same hardware, hours apart:
#
#   session   stock    1000mV/3000   conclusion
#   16:28     76 896       82 329    +7.1%  (faster)
#   19:14     82 244       79 531    -3.3%  (slower)
#
# Same setting. Same card. Delivered clock identical in all four runs (2802-2813 MHz,
# a 0.4% spread) while scores spanned 7%. GPU utilization flat at 92-93.5%. The effect
# being measured and the between-block noise were the same size, so the sign of the
# result was decided by when it was run — and a +7.1% figure was reported with
# confidence for hours on that basis.
#
# THE FIX IS INTERLEAVING, NOT MORE PASSES. Repeating a block makes a drifting
# measurement more precisely wrong. Alternating the two arms within one session makes
# drift hit BOTH arms nearly equally, and the paired difference cancels it.
#
# COUNTERBALANCED (ABBA), NOT ALTERNATING (ABAB). Strict alternation puts A earlier than
# B in every pair, so any warming trend is charged systematically to B. ABBA pairs run
# A,B then B,A: the position bias cancels across each block of four. This matters here
# because scores decline measurably WITHIN a run as the card heats.
#
# Usage (root — curve edits need it; the benchmark is dropped to the caller):
#   sudo ./tools/gpu-ab-compare.sh --mv 1000 --mhz 3000              # 6 pairs, ~35 min
#   sudo ./tools/gpu-ab-compare.sh --mv 1000 --mhz 3000 --pairs 4    # ~23 min
#   sudo ./tools/gpu-ab-compare.sh --mv 1000 --mhz 3000 --screen 1
#
# The curve is reset to stock on ANY exit, including Ctrl-C and a crash.

set -uo pipefail
export LC_ALL=C

MV=0; MHZ=0; PAIRS=6; SCREEN=0; ASTEROIDS=200000; WIDTH=2560; HEIGHT=1440

usage() { sed -n '2,37p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mv) MV=$2; shift 2 ;;
    --mhz) MHZ=$2; shift 2 ;;
    --pairs) PAIRS=$2; shift 2 ;;
    --screen) SCREEN=$2; shift 2 ;;
    --asteroids) ASTEROIDS=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (applies curve edits); re-run with sudo" >&2; exit 1; }
[ "$MV" -gt 0 ] && [ "$MHZ" -gt 0 ] || { echo "need --mv and --mhz" >&2; usage 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
HERE="$(cd "$(dirname "$0")" && pwd)"
FLATTEN="$HERE/gpu-flatten.sh"
NVCURVE="${NVCURVE:-$home/.local/bin/nvcurve}"
[ -x "$FLATTEN" ] || { echo "gpu-flatten.sh missing" >&2; exit 1; }

find_tool() {
  local var=$1; shift
  local v=${!var:-}
  [ -n "$v" ] && [ -x "$v" ] && { echo "$v"; return 0; }
  local c e
  for c in "$@"; do for e in $c; do [ -x "$e" ] && { echo "$e"; return 0; }; done; done
  return 1
}
GM=$(find_tool GRAVITYMARK \
      "$home/Downloads/GravityMark_"*"_linux/bin/GravityMark.x64" \
      "$home/dev/vendor/GravityMark"*"/bin/GravityMark.x64" \
      "/opt/GravityMark"*"/bin/GravityMark.x64") || {
  echo "GravityMark not found. Set GRAVITYMARK=/path/to/GravityMark.x64" >&2; exit 1; }

OUT="$home/bench/ab-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/ab.log"
say() { echo "$*" | tee -a "$LOG"; sync; }

cleanup() { "$NVCURVE" write --reset >/dev/null 2>&1; }
trap cleanup EXIT INT TERM

AS_USER=()
if [ -n "${SUDO_USER:-}" ]; then
  AS_USER=( sudo -u "$SUDO_USER"
            DISPLAY="${DISPLAY:-:0}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
            XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")"
            XAUTHORITY="${XAUTHORITY:-$home/.Xauthority}" HOME="$home" )
fi
GM_ARGS=( -vk -raytracing 1 -temporal 1 -fullscreen 1 -screen "$SCREEN"
          -benchmark 1 -count 1 -close 1
          -asteroids "$ASTEROIDS" -width "$WIDTH" -height "$HEIGHT" )

# One pass. $1 = arm (A=stock, B=setting), $2 = index. Appends "arm idx score temp0 W MHz".
N=0
one_pass() {
  local arm=$1 idx=$2 plog="$OUT/pass-$(printf '%02d' "$idx")-$1.log"
  if [ "$arm" = A ]; then "$NVCURVE" write --reset >/dev/null 2>&1
  else "$FLATTEN" --mv "$MV" --mhz "$MHZ" >/dev/null 2>&1 || { say "  flatten FAILED — aborting"; exit 1; }
  fi
  local t0; t0=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
  # sample sensors for the duration of the pass
  ( while :; do nvidia-smi --query-gpu=clocks.sm,power.draw --format=csv,noheader,nounits \
      | tr -d ' ' | tr ',' ' '; sleep 3; done > "$OUT/s-$idx-$arm.txt" ) &
  local sp=$!
  ( cd "$(dirname "$GM")" && timeout -k 20 400 "${AS_USER[@]}" \
      ./"$(basename "$GM")" "${GM_ARGS[@]}" ) >"$plog" 2>&1
  local rc=$?
  kill $sp 2>/dev/null; wait $sp 2>/dev/null
  local sc; sc=$(grep -oE 'Score: [0-9]+' "$plog" | grep -oE '[0-9]+' | head -1)
  if [ "$rc" -ne 0 ] || [ -z "$sc" ]; then
    say "  pass $idx [$arm]: FAILED rc=$rc — see $plog"
    return 1
  fi
  read -r mf mw < <(awk '$2+0>100 {n++; f+=$1; w+=$2} END{if(n) printf "%.0f %.0f", f/n, w/n; else printf "0 0"}' "$OUT/s-$idx-$arm.txt")
  printf '%s\t%d\t%d\t%s\t%s\t%s\n' "$arm" "$idx" "$sc" "$t0" "$mw" "$mf" >> "$OUT/passes.tsv"
  sync
  say "  pass $idx [$arm $([ "$arm" = A ] && echo stock || echo "${MV}/${MHZ}")]: score $sc   ${mf} MHz  ${mw} W  start ${t0}C"
  return 0
}

say "=== interleaved A/B: stock vs ${MV} mV / ${MHZ} MHz ==="
say "pairs:   $PAIRS  ($(( PAIRS * 2 )) passes, ~$(( PAIRS * 2 * 175 / 60 )) min)"
say "order:   counterbalanced ABBA — A,B then B,A each block of four"
say "screen:  $SCREEN     scene: ${WIDTH}x${HEIGHT}, ${ASTEROIDS} asteroids, Vulkan RT"
say "output:  $OUT"
say ""
say "Block comparison (four passes at A, then four at B) charges any drift between the"
say "blocks to the setting. On 2026-08-04 that gave +7.1% at 16:28 and -3.3% at 19:14"
say "for the SAME setting, with delivered clock identical to 0.4% in all four runs."
say "Interleaving makes drift hit both arms; the paired difference cancels it."
say ""
: > "$OUT/passes.tsv"

idx=0
for p in $(seq 1 "$PAIRS"); do
  # ABBA: odd pairs run A first, even pairs run B first
  if [ $(( p % 2 )) -eq 1 ]; then order="A B"; else order="B A"; fi
  for arm in $order; do
    idx=$(( idx + 1 ))
    one_pass "$arm" "$idx" || { say "aborting after a failed pass"; break 2; }
  done
done

"$NVCURVE" write --reset >/dev/null 2>&1
say ""
say "═══════════════════════════════════════════════"

python3 - "$OUT/passes.tsv" "$MV" "$MHZ" <<'PY' | tee -a "$LOG"
import sys, math
rows=[l.split('\t') for l in open(sys.argv[1]) if l.strip()]
A=[(int(r[1]), int(r[2]), float(r[4]), float(r[5])) for r in rows if r[0]=='A']
B=[(int(r[1]), int(r[2]), float(r[4]), float(r[5])) for r in rows if r[0]=='B']
if len(A)<2 or len(B)<2:
    print("  Not enough passes to compare."); sys.exit()
def mean(x): return sum(x)/len(x)
sa, sb = [a[1] for a in A], [b[1] for b in B]
wa, wb = [a[2] for a in A], [b[2] for b in B]
fa, fb = [a[3] for a in A], [b[3] for b in B]
print(f"  {'':10} {'stock':>10} {'setting':>10} {'change':>10}")
print(f"  {'score':10} {mean(sa):10.0f} {mean(sb):10.0f} {(mean(sb)/mean(sa)-1)*100:+9.1f}%")
print(f"  {'watts':10} {mean(wa):10.0f} {mean(wb):10.0f} {(mean(wb)/mean(wa)-1)*100:+9.1f}%")
print(f"  {'MHz':10} {mean(fa):10.0f} {mean(fb):10.0f} {(mean(fb)/mean(fa)-1)*100:+9.1f}%")
print()
# Paired differences: pair the k-th A with the k-th B. With ABBA ordering each pair
# contains one of each in both positions across consecutive blocks, so position bias
# cancels. This is what makes the difference resistant to drift.
n=min(len(sa),len(sb))
d=[sb[i]-sa[i] for i in range(n)]
md=mean(d)
if n>1:
    sd=math.sqrt(sum((x-md)**2 for x in d)/(n-1))
    se=sd/math.sqrt(n)
    t=md/se if se>0 else 0.0
    # 95% CI, t-critical for small n (two-sided)
    tc={2:12.706,3:4.303,4:3.182,5:2.776,6:2.571,7:2.447,8:2.365,9:2.306,10:2.262}.get(n,2.0)
    lo,hi=md-tc*se, md+tc*se
    pct=lambda v: v/mean(sa)*100
    print(f"  PAIRED DIFFERENCE (setting - stock), n={n} pairs")
    print(f"    mean   {md:+.0f} points  ({pct(md):+.2f}%)")
    print(f"    95% CI [{lo:+.0f}, {hi:+.0f}]  ([{pct(lo):+.2f}%, {pct(hi):+.2f}%])")
    print(f"    t = {t:+.2f}")
    print()
    if lo <= 0 <= hi:
        print("  ► NO MEASURABLE PERFORMANCE DIFFERENCE.")
        print("    The interval spans zero: this data cannot distinguish the setting from")
        print("    stock on score. That is a real result, not a failure — it means any")
        print(f"    true effect is smaller than +/-{max(abs(pct(lo)),abs(pct(hi))):.1f}%, which is what this many")
        print("    pairs can resolve. Judge the setting on POWER, which is separable.")
    elif md>0:
        print(f"  ► FASTER by {pct(md):.1f}% — interval excludes zero, so the sign is trustworthy.")
    else:
        print(f"  ► SLOWER by {abs(pct(md)):.1f}% — interval excludes zero, so the sign is trustworthy.")
print()
# Drift check: is score trending across the session regardless of arm?
allp=sorted([(int(r[1]), int(r[2])) for r in rows])
k=len(allp)
if k>=4:
    xm=mean([p[0] for p in allp]); ym=mean([p[1] for p in allp])
    num=sum((p[0]-xm)*(p[1]-ym) for p in allp); den=sum((p[0]-xm)**2 for p in allp)
    slope=num/den if den else 0
    tot=slope*(allp[-1][0]-allp[0][0])
    print(f"  drift across the session: {slope:+.0f} points/pass, {tot/ym*100:+.1f}% end-to-end")
    if abs(tot/ym*100) > 2:
        print("    Substantial drift IS present — which is exactly what block comparison")
        print("    would have charged to the setting. Interleaving is why it did not.")
    else:
        print("    Little drift this session. The block comparison would have been safe here;")
        print("    it was not on 2026-08-04, and there is no way to know in advance.")
PY

say ""
say "Curve reset to stock. Nothing persists across a reboot."
say "Full data: $OUT/passes.tsv"
chown -R "${SUDO_USER:-root}" "$OUT" 2>/dev/null
