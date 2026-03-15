#!/usr/bin/env bash
# Check XG27JCG current mode (5K vs 2K) via DDC and GNOME.
# Bus 5 = XG27JCG (DP-2)

echo "=== DDC (monitor-reported) ==="
freq=$(ddcutil getvcp 0xAE --bus 5 2>/dev/null | grep -oP '[\d.]+(?= hz)')
fd=$(ddcutil getvcp 0xFD --bus 5 2>/dev/null | grep -oP 'sh=0x\K[0-9a-f]+|sl=0x\K[0-9a-f]+' | tr '\n' ',')
echo "  Refresh rate (0xAE): ${freq} Hz"
echo "  0xFD: sh,sl = $fd"
if [[ "$freq" =~ ^3[0-9][0-9] ]]; then
    echo "  → 2K mode (2560×1440 @ 330Hz)"
elif [[ "$freq" =~ ^1[78][0-9] ]]; then
    echo "  → 5K mode (5120×2880 @ 180Hz)"
else
    echo "  → Unknown mode"
fi

echo ""
echo "=== GNOME (actual resolution) ==="
# Parse GetCurrentState for XG27JCG (DP-2) current mode
out=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null)
# Find DP-2 / XG27JCG and its is-current mode
if echo "$out" | grep -q "DP-2.*XG27JCG"; then
    mode=$(echo "$out" | grep -oP "'[0-9]+x[0-9]+@[0-9.]+[^']*'" | head -1)
    res=$(echo "$out" | grep -oP "2560x1440|5120x2880" | head -1)
    echo "  XG27JCG (DP-2): $res"
    if [[ "$res" == "5120x2880" ]]; then
        echo "  → 5K mode"
    elif [[ "$res" == "2560x1440" ]]; then
        echo "  → 2K mode"
    fi
fi
