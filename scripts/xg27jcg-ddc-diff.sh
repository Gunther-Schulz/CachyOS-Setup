#!/usr/bin/env bash
# Capture DDC state before/after OSD change to find which VCP code changed.
# Usage: ./xg27jcg-ddc-diff.sh
# 1. Run - it captures "before" state
# 2. Switch "Frame Rate Boost" via OSD
# 3. Press Enter - it captures "after" and diffs

BUS=5  # XG27JCG from detect (card1-DP-2 = i2c-5)

capture() {
    for code in E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF; do
        ddcutil getvcp "0x$code" --bus "$BUS" 2>/dev/null | grep -oP 'sl=0x\K[0-9a-f]+|sh=0x\K[0-9a-f]+|mh=0x\K[0-9a-f]+|ml=0x\K[0-9a-f]+' | paste -sd ' ' -
    done | while read -r line; do echo "$line"; done
}

# Simpler: just get the raw values
capture_simple() {
    for code in E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF; do
        out=$(ddcutil getvcp "0x$code" --bus "$BUS" 2>/dev/null)
        echo "$code $out"
    done
}

BEFORE="/tmp/xg27jcg-before.txt"
AFTER="/tmp/xg27jcg-after.txt"

echo "=== BEFORE: Switch Frame Rate Boost OFF (5K mode) if not already, then press Enter ==="
read -r
capture_simple > "$BEFORE"
echo "Captured. Now switch Frame Rate Boost ON (2K mode) via OSD, then press Enter."
read -r
capture_simple > "$AFTER"
echo "=== DIFF (codes that changed) ==="
diff "$BEFORE" "$AFTER" | grep -E '^[<>]' || echo "No changes detected"
