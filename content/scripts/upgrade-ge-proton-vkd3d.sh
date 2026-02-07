#!/usr/bin/env bash
# Upgrade VKD3D-Proton in GE-Proton (proton-ge-custom) to 3.x (e.g. for better UE5/ARC Raiders performance).
#
# Option A – Use AUR package (recommended):
#   1. Install: yay -S vkd3d-proton-bin   (or paru -S vkd3d-proton-bin)
#   2. Run this script with sudo.
#
# Option B – Use a downloaded release:
#   1. Download vkd3d-proton-3.x.tar.zst from https://github.com/HansKristian-Work/vkd3d-proton/releases
#   2. Extract it to a folder, then: sudo ./upgrade-ge-proton-vkd3d.sh /path/to/extracted/vkd3d-proton
#
# Target: GE-Proton from AUR (proton-ge-custom-bin) at /usr/share/steam/compatibilitytools.d/proton-ge-custom
# If you installed GE-Proton via ProtonUp Qt elsewhere, pass its root as first arg:
#   sudo ./upgrade-ge-proton-vkd3d.sh /home/you/.steam/root/compatibilitytools.d/GE-Proton10-29
#
# Revert: reinstall proton-ge-custom-bin or re-download GE-Proton and replace the folder.

set -e

# GE-Proton root (AUR install); contains files/lib/wine/vkd3d-proton
GE_PROTON_ROOT="${GE_PROTON_ROOT:-/usr/share/steam/compatibilitytools.d/proton-ge-custom}"
PROTON_VKD3D="$GE_PROTON_ROOT/files/lib/wine/vkd3d-proton"
AUR_VKD3D="/usr/share/vkd3d-proton"

usage() {
    echo "Usage: $0 [GE_PROTON_ROOT_OR_SOURCE] [SOURCE_DIR]"
    echo "  No args: upgrade GE-Proton at $GE_PROTON_ROOT using AUR vkd3d-proton-bin"
    echo "  One arg:"
    echo "    - If dir contains files/lib/wine/vkd3d-proton → use as GE-Proton root, source from AUR"
    echo "    - Else → use as vkd3d-proton release dir (extracted x86_64-windows/ etc.)"
    echo "  Two args: GE_PROTON_ROOT SOURCE_DIR"
    echo ""
    echo "Install AUR source: yay -S vkd3d-proton-bin"
    exit 1
}

# Resolve GE-Proton root and source dir from args
SRC=""
if [[ -n "${1:-}" ]]; then
    if [[ "$1" == -* ]] || [[ ! -d "$1" ]]; then
        usage
    fi
    if [[ -d "$1/files/lib/wine/vkd3d-proton" ]]; then
        GE_PROTON_ROOT="$1"
        PROTON_VKD3D="$GE_PROTON_ROOT/files/lib/wine/vkd3d-proton"
    else
        SRC="$1"
    fi
fi
if [[ -n "${2:-}" ]]; then
    [[ -d "$2" ]] || usage
    GE_PROTON_ROOT="$1"
    SRC="$2"
    PROTON_VKD3D="$GE_PROTON_ROOT/files/lib/wine/vkd3d-proton"
fi

if [[ ! -d "$PROTON_VKD3D" ]]; then
    echo "Error: GE-Proton not found at $PROTON_VKD3D"
    echo "Set GE_PROTON_ROOT or pass the GE-Proton root directory (e.g. from ProtonUp Qt install)."
    exit 1
fi

# Require root when target is under /usr (AUR install)
if [[ "$PROTON_VKD3D" == /usr/* ]] && [[ $(id -u) -ne 0 ]]; then
    echo "Error: Target is under /usr. Run with sudo:"
    echo "  sudo $0 ${1:+$1} ${2:+$2}"
    exit 1
fi

if [[ -z "$SRC" ]]; then
    if [[ ! -d "$AUR_VKD3D" ]]; then
        echo "Error: AUR vkd3d-proton not found at $AUR_VKD3D"
        echo "Install with: yay -S vkd3d-proton-bin   (or paru -S vkd3d-proton-bin)"
        echo "Or run: $0 /path/to/extracted/vkd3d-proton"
        exit 1
    fi
    SRC="$AUR_VKD3D"
fi

echo "Source: $SRC"
if [[ -f "$SRC/version" ]]; then
    echo "Source version: $(cat "$SRC/version")"
else
    echo "Source version file not found; copying DLLs only."
fi
echo "Target: $PROTON_VKD3D"
echo ""

# AUR vkd3d-proton-bin uses x64/ and x86/; GitHub release uses x86_64-windows/ and i386-windows/
# Map: source_dir -> target_dir
copied=0
for src_arch in x86_64-windows i386-windows; do
    if [[ -d "$SRC/$src_arch" ]]; then
        for dll in d3d12.dll d3d12core.dll; do
            if [[ -f "$SRC/$src_arch/$dll" ]]; then
                echo "Installing $src_arch/$dll"
                install -m 644 "$SRC/$src_arch/$dll" "$PROTON_VKD3D/$src_arch/"
                copied=1
            fi
        done
    fi
done
# AUR layout: x64 -> x86_64-windows, x86 -> i386-windows
if [[ $copied -eq 0 ]] && [[ -d "$SRC/x64" ]]; then
    for src_arch in x64 x86; do
        dst_arch="x86_64-windows"
        [[ "$src_arch" == x86 ]] && dst_arch="i386-windows"
        if [[ -d "$SRC/$src_arch" ]]; then
            for dll in d3d12.dll d3d12core.dll; do
                if [[ -f "$SRC/$src_arch/$dll" ]]; then
                    echo "Installing $src_arch/$dll -> $dst_arch/"
                    install -m 644 "$SRC/$src_arch/$dll" "$PROTON_VKD3D/$dst_arch/"
                    copied=1
                fi
            done
        fi
    done
fi
[[ $copied -eq 0 ]] && { echo "Error: No DLLs found in source (expected x86_64-windows/ and i386-windows/ or AUR layout x64/ and x86/)"; exit 1; }

if [[ -f "$SRC/version" ]]; then
    install -m 644 "$SRC/version" "$PROTON_VKD3D/"
else
    # AUR doesn't ship a version file; write one so we know we upgraded (vkd3d-proton-bin is 3.0b)
    if [[ "$SRC" == "$AUR_VKD3D" ]]; then
        echo "4d4abaa230fed54c2bf12b56cf4e4cd2286bd034 vkd3d-proton (v3.0b from AUR vkd3d-proton-bin)" > "$PROTON_VKD3D/version"
        echo "Wrote version file (AUR vkd3d-proton-bin = v3.0b)."
    fi
fi

echo "Done. Current vkd3d-proton version:"
cat "$PROTON_VKD3D/version" 2>/dev/null || true
