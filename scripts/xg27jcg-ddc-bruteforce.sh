#!/usr/bin/env bash
# Interactive brute-force of XG27JCG VCP codes for Frame Rate Boost (5K/2K switch).
# Each setvcp is shown first — you confirm before it runs.
# Requires: ddcutil, i2c_dev loaded (sudo modprobe i2c-dev).

set -e

BUS="${XG27JCG_BUS:-5}"  # Override with env, e.g. XG27JCG_BUS=5
FOUND_FILE="/tmp/xg27jcg-ddc-found.txt"

# Check ddcutil
if ! command -v ddcutil &>/dev/null; then
    echo "ERROR: ddcutil not installed. pacman -S ddcutil"
    exit 1
fi

if ! lsmod | grep -q '^i2c_dev '; then
    echo "ERROR: i2c_dev not loaded. Run: sudo modprobe i2c-dev"
    exit 1
fi

# Must run interactively — read uses /dev/tty because stdin is piped from build_candidates
if [[ ! -t 0 ]]; then
    echo "ERROR: Run interactively in a terminal (stdin is not a TTY)."
    exit 1
fi

echo "=== XG27JCG DDC brute-force (interactive) ==="
echo "Bus: $BUS  (set XG27JCG_BUS=N to override)"
echo "Each command will be shown. Enter or y=run, n=skip, q=quit, s=run & save. (16 skipped.)"
echo ""

# Build candidate list: "code value" per line
# 0x03 = soft controls (simulate button); 1,2=OSD menu; 16=display OFF (dangerous!); 20=caused issues
# 0xE0-0xFF = manufacturer codes; 0/1/257 common for on/off or 2K mode
build_candidates() {
    # Soft controls 0x03 — skip 16 (display off!), 20 (doc)
    for v in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 17 18 19 21 22 23 24 25; do
        echo "03 $v"
    done
    # Manufacturer codes: try 0, 1, 257 (2K) for each
    for code in E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF; do
        echo "$code 0"
        echo "$code 1"
        echo "$code 257"
    done
}

count=0
total=$(build_candidates | wc -l)

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    code="${line%% *}"
    value="${line#* }"
    count=$((count + 1))
    hex="0x$code"

    cmd="ddcutil setvcp $hex $value --bus $BUS"
    echo "[$count/$total] $cmd"
    echo -n "  Run? [Y/n/q/s]: "
    read -r reply </dev/tty

    reply="${reply,,}"
    reply="${reply//[[:space:]]/}"
    case "$reply" in
        q|quit) echo "Quit."; exit 0 ;;
        n|no) echo "  Skipped."; continue ;;
        s) echo "  Running & saving..."; $cmd 2>&1; echo "$cmd" > "$FOUND_FILE"; echo "  Saved to $FOUND_FILE"; exit 0 ;;
        y|yes|"")
            echo "  Running..."
            if $cmd 2>&1; then
                echo "  OK."
            else
                echo "  Command failed or no effect."
            fi
            ;;
        *) echo "  Unknown. Skipping." ;;
    esac
done < <(build_candidates)

echo "Done. Tried $count commands."
