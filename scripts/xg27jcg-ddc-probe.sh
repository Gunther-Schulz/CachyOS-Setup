#!/usr/bin/env bash
# Probe ASUS XG27JCG via DDC/CI to discover VCP codes (especially dual-mode 5K/2K switch).
# Requires: ddcutil, i2c_dev loaded (sudo modprobe i2c-dev if blacklisted).
# Output saved to /tmp/xg27jcg-ddc-probe-*.txt

set -e
OUT="/tmp/xg27jcg-ddc-probe-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee -a "$OUT") 2>&1

echo "=== XG27JCG DDC probe $(date) ==="
echo "Output: $OUT"
echo

# Check ddcutil
if ! command -v ddcutil &>/dev/null; then
    echo "ERROR: ddcutil not installed. Install with: pacman -S ddcutil"
    exit 1
fi

# Check i2c_dev
if ! lsmod | grep -q '^i2c_dev '; then
    echo "ERROR: i2c_dev not loaded. With i2c_dev blacklisted, run:"
    echo "  sudo modprobe i2c-dev"
    echo "Then re-run this script."
    exit 1
fi
echo "i2c_dev: loaded"
echo

# Detect monitors
echo "=== ddcutil detect ==="
ddcutil detect -v
echo

# Extract I2C bus paths (handles both "I2C bus:  /dev/i2c-N" and "I2C bus: /dev/i2c-N")
get_buses() { ddcutil detect 2>/dev/null | grep -oE '/dev/i2c-[0-9]+' | sort -u; }

# Capabilities (may be unreliable per ddcutil docs)
echo "=== ddcutil capabilities ==="
for bus in $(get_buses); do
    echo "--- $bus ---"
    ddcutil capabilities --bus "$bus" 2>/dev/null || echo "(capabilities failed)"
done
echo

# All known VCP features
echo "=== ddcutil getvcp all (per bus) ==="
for bus in $(get_buses); do
    echo "--- $bus ---"
    ddcutil getvcp all --bus "$bus" 2>/dev/null || echo "(getvcp all failed)"
done
echo

# Probe manufacturer-specific range (0xE0-0xFF) - try common codes
echo "=== Manufacturer VCP scan (0xE0-0xFF) ==="
echo "Trying common manufacturer codes. Non-zero/readable values may indicate mode/resolution control."
for bus in $(get_buses); do
    echo "--- $bus ---"
    for code in E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF; do
        val=$(ddcutil getvcp "0x$code" --bus "$bus" 2>/dev/null | grep -oP 'current value: *\K.*' || echo "")
        if [[ -n "$val" && "$val" != "0" && "$val" != "0 (sl=0)" ]]; then
            echo "  0x$code: $val"
        fi
    done
done
echo

echo "=== Done. Full output: $OUT ==="
