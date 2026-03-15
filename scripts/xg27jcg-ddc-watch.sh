#!/usr/bin/env bash
# Poll manufacturer VCP codes and report when any change. Run this, then switch
# "Frame Rate Boost" via OSD during the 30-second window.
# Usage: ./xg27jcg-ddc-watch.sh

BUS=5
# Focus on likely candidates (F0-FD) - full scan takes ~10s per poll
CODES="E2 E3 E4 E8 E9 EB EC ED F0 F1 F2 F3 F4 F5 F6 F7 F8 FA FB FC FD"

capture() {
    for code in $CODES; do
        ddcutil getvcp "0x$code" --bus "$BUS" 2>/dev/null | grep -oE 'mh=0x[0-9a-f]+|ml=0x[0-9a-f]+|sh=0x[0-9a-f]+|sl=0x[0-9a-f]+' | tr '\n' ' '
        echo
    done | paste - - - - | while IFS=$'\t' read -r a b c d; do echo "$a $b $c $d"; done
}

# Simpler: get sl value per code (most likely to change for toggles)
get_sl_values() {
    for code in $CODES; do
        sl=$(ddcutil getvcp "0x$code" --bus "$BUS" 2>/dev/null | grep -oP 'sl=0x\K[0-9a-f]+')
        echo "$code=$sl"
    done
}

echo "Polling for 30 seconds. Switch Frame Rate Boost via OSD now!"
prev=$(get_sl_values)
for i in $(seq 1 15); do
    sleep 2
    curr=$(get_sl_values)
    diff <(echo "$prev") <(echo "$curr") && continue
    echo "=== CHANGE DETECTED at ${i}x2s ==="
    diff <(echo "$prev") <(echo "$curr") | grep -E '^[<>]' || true
    prev=$curr
done
echo "Done."
