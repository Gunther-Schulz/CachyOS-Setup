#!/usr/bin/env bash
# Print the VKD3D-Proton version for a Proton installation.
# Use this to be SURE whether a Proton (GE-Proton, CachyOS, Valve, etc.) has v3.x.
#
# Usage:
#   ./check-proton-vkd3d-version.sh [PATH]
#   No path: scan common locations (compatibilitytools.d, steamapps/common).
#   PATH:    e.g. ~/.steam/steam/compatibilitytools.d/GE-Proton10-28
#            or   /usr/share/steam/compatibilitytools.d/proton-cachyos-slr
#
# Version string meaning:
#   vkd3d-1.1-xxxx  = old 1.x line (not 2.x or 3.x)
#   vkd3d-2.x       = 2.x release
#   v3.0 / vkd3d-3  = 3.x (or check for "3.0" in the line)

set -e

scan_dirs=(
    "$HOME/.steam/steam/compatibilitytools.d"
    "$HOME/.steam/root/steamapps/common"
    "$HOME/.local/share/Steam/compatibilitytools.d"
    "/usr/share/steam/compatibilitytools.d"
)

check_one() {
    local dir="$1"
    local vf="$dir/files/lib/wine/vkd3d-proton/version"
    if [[ -f "$vf" ]]; then
        echo "--- $dir ---"
        cat "$vf"
        echo ""
        return 0
    fi
    return 1
}

if [[ -n "${1:-}" ]]; then
    if [[ ! -d "$1" ]]; then
        echo "Error: not a directory: $1"
        exit 1
    fi
    if ! check_one "$(realpath "$1")"; then
        echo "No vkd3d-proton/version found under $1"
        exit 1
    fi
    exit 0
fi

found=0
for base in "${scan_dirs[@]}"; do
    [[ -d "$base" ]] || continue
    for dir in "$base"/*; do
        [[ -d "$dir" ]] || continue
        if check_one "$dir"; then
            found=1
        fi
    done
done
if [[ $found -eq 0 ]]; then
    echo "No Proton installations with vkd3d-proton/version found in:"
    printf '  %s\n' "${scan_dirs[@]}"
    exit 1
fi
