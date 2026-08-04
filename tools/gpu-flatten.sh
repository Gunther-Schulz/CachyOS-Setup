#!/usr/bin/env bash
# gpu-flatten.sh — Afterburner-style V/F curve flatten, from the command line.
#
# WHAT A FLATTEN IS, and why it is different from a global offset:
#   A global offset raises EVERY point, including the top of the curve — which is why
#   +400 hung on 2026-08-04 (top point pushed to 3580 MHz @ 1240 mV).
#   A flatten instead picks an ANCHOR voltage, sets the frequency there, and pins every
#   HIGHER-voltage point to that SAME frequency. The card then gains nothing by raising
#   voltage past the anchor, so it stops there — the curve becomes a VOLTAGE CEILING.
#   Points BELOW the anchor are untouched, so idle behaviour is preserved.
#
# WHY THAT IS THE QUIET SETTING. Power goes as V²·f, so trading a lot of voltage for a
# little clock is strongly favourable. Measured stock on this card: 2803 MHz @ 1075 mV,
# 370 W. A flatten at 890 mV / 2827 MHz would be ~stock performance at ~256 W — roughly
# −31 % power for +0.9 % clock, modelled from the card's own curve.
#
# THE ALGORITHM IS NOT INVENTED HERE. Taken from NVCurve's own frontend
# (frontend/src/store/curveStore.ts, flattenToAnchor):
#     anchorEffective = anchorPoint.freq_khz + anchorDelta
#     for each selected point:  delta[i] = anchorEffective - point[i].freq_khz
# i.e. delta per point = target frequency − that point's OWN base frequency. Points
# above the anchor get NEGATIVE deltas, which is expected and correct.
#
# Usage (root — nvcurve writes require it):
#   sudo ./tools/gpu-flatten.sh --mv 950 --mhz 2800          # apply
#   sudo ./tools/gpu-flatten.sh --mv 950 --mhz 2800 --dry-run # show the plan only
#   sudo ./tools/gpu-flatten.sh --reset                       # back to stock
#
# START HIGH AND WALK DOWN. 950 mV needs ~+220 MHz at the anchor, well inside what this
# card has already proven. 890 mV needs ~+1000 MHz there and is untested. Prove the
# method at 950, soak it, then step down 925 → 900 → 890, re-soaking each time:
#   sudo ./tools/gpu-soak.sh --screen 1 --passes 10

set -uo pipefail
export LC_ALL=C

ANCHOR_MV=0
TARGET_MHZ=0
DRY=0
RESET=0

usage() { sed -n '2,32p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mv) ANCHOR_MV=$2; shift 2 ;;
    --mhz) TARGET_MHZ=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --reset) RESET=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "needs root (nvcurve writes); re-run with sudo" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
NVCURVE="$home/.local/bin/nvcurve"
[ -x "$NVCURVE" ] || NVCURVE=$(command -v nvcurve) || true
[ -n "${NVCURVE:-}" ] && [ -x "$NVCURVE" ] || { echo "nvcurve not found" >&2; exit 1; }

if [ "$RESET" = 1 ]; then "$NVCURVE" write --reset; exit $?; fi
[ "$ANCHOR_MV" -gt 0 ] && [ "$TARGET_MHZ" -gt 0 ] || { echo "need --mv and --mhz" >&2; usage 1; }

CURVE=$("$NVCURVE" read --json 2>/dev/null) || { echo "could not read the curve" >&2; exit 1; }

# Build the edit plan. Only GPU-domain points at or above the anchor voltage are touched;
# memory points and everything below the anchor are left alone.
PLAN=$(echo "$CURVE" | python3 -c '
import json,sys
d=json.load(sys.stdin)
mv=int(sys.argv[1]); mhz=int(sys.argv[2])
pts=[p for p in d["vf_curve"] if p.get("domain")=="gpu" and p["volt_uV"]>0]
sel=[p for p in pts if p["volt_uV"]/1000.0 >= mv]
if not sel:
    print("ERR no GPU points at or above %d mV" % mv, file=sys.stderr); sys.exit(1)
anchor=min(sel, key=lambda p: p["volt_uV"])
for p in sel:
    delta = mhz - p["freq_kHz"]/1000.0
    print("%d\t%.0f\t%.0f\t%.0f" % (p["index"], p["volt_uV"]/1000.0, p["freq_kHz"]/1000.0, delta))
print("#anchor\t%d\t%.0f\t%.0f" % (anchor["index"], anchor["volt_uV"]/1000.0, anchor["freq_kHz"]/1000.0), file=sys.stderr)
' "$ANCHOR_MV" "$TARGET_MHZ") || exit 1

N=$(echo "$PLAN" | grep -c .)
echo "=== flatten plan: everything at/above ${ANCHOR_MV} mV → ${TARGET_MHZ} MHz ==="
echo "$PLAN" | awk -F'\t' 'BEGIN{printf "%6s %8s %10s %10s\n","point","mV","base MHz","delta"}
                           {printf "%6s %8s %10s %+10s\n",$1,$2,$3,$4}' | head -40
echo "--- $N point(s) ---"

# ±1000 MHz is nvcurve's own safety cap; a plan outside it cannot be applied and is
# better refused here than half-written to the hardware.
OUT=$(echo "$PLAN" | awk -F'\t' '$4>1000 || $4<-1000 {print}' )
[ -n "$OUT" ] && { echo "REFUSING: some deltas exceed the ±1000 MHz range:" >&2; echo "$OUT" >&2; exit 1; }

if [ "$DRY" = 1 ]; then echo; echo "(dry run — nothing written)"; exit 0; fi

echo
echo "applying ..."
FAIL=0
while IFS=$'\t' read -r idx mv base delta; do
  [ -n "$idx" ] || continue
  "$NVCURVE" write --point "$idx" --delta "$delta" >/dev/null 2>&1 || { echo "  point $idx FAILED"; FAIL=1; }
done <<< "$PLAN"

[ "$FAIL" = 1 ] && { echo "one or more writes failed — resetting to stock for safety"; "$NVCURVE" write --reset; exit 1; }
echo "done. Verify with:  sudo $NVCURVE read | head -30"
echo
echo "NOT PERSISTENT — a reboot returns the card to stock."
echo "Validate before trusting it:  sudo ./tools/gpu-soak.sh --screen 1 --passes 10"
