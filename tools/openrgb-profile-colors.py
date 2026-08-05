#!/usr/bin/env python3
"""openrgb-profile-colors.py — read the colors OUT of an OpenRGB .orp profile.

Why this exists: the RGB controllers are write-only and OpenRGB's GUI never
populates its pickers from a loaded profile (observed on 1.0rc3, 2026-08-05),
so the saved values are unreadable exactly when you want to adjust from them.
This prints them. Usage:

    ./tools/openrgb-profile-colors.py                     # the default profile
    ./tools/openrgb-profile-colors.py path/to/other.orp

HOW IT PARSES, and why it is safe against format drift: each controller block
is size-prefixed, so block boundaries are exact regardless of what fields a
new format version adds in the middle. The device name is at a fixed offset
from the block START (type + name is the first string), and the per-LED color
array is the LAST field (ushort count + count*4 bytes) — anchored from the
block END by requiring the count to exactly close the block. If that geometry
ever stops self-confirming (a future version appends fields after the colors),
this refuses loudly per block instead of misreading — it can never silently
print wrong colors, only "unparseable".

Verified against known truth at build time: the 2026-08-05 profile, whose
colors were set by hand minutes earlier (RAM 0623FF, board FF2600).
"""
import pathlib
import struct
import sys

MAGIC = b"OPENRGB_PROFILE\x00"
# Bytes AFTER the color array, per format version — v5 verified empirically
# (an empty ushort field + a uint32). An unknown version scans 0..16 instead.
KNOWN_TAIL = {5: 6}


def parse_block(d: bytes, version: int) -> tuple[str, list[str]]:
    """(device name, color hexes) from one size-prefixed controller block."""
    # front anchor: uint32 size, uint32 type, then name as (ushort len, bytes)
    name_len = struct.unpack_from("<H", d, 8)[0]
    name = d[10:10 + name_len].rstrip(b"\x00").decode(errors="replace")
    # end anchor: the color array is (ushort count + count*4 bytes) just before
    # the version tail. Two requirements before trusting a candidate: the count
    # closes the block exactly, and every color's 4th byte is 0x00 (OpenRGB's
    # RGBColor never uses it — this rejects counts that accidentally appear
    # INSIDE the color bytes). Ambiguity refuses rather than guesses: this tool
    # can print "unparseable", never wrong colors.
    end = len(d)
    tails = [KNOWN_TAIL[version]] if version in KNOWN_TAIL else range(0, 17)
    hits = []
    for t in tails:
        for n in range(1, 4096):
            p = end - t - 2 - 4 * n
            if p < 10:
                break
            if (struct.unpack_from("<H", d, p)[0] == n
                    and all(d[end - t - 4 * (n - i) + 3] == 0 for i in range(n))):
                hits.append((t, n))
    if len(hits) != 1:
        return name, []
    t, n = hits[0]
    colors = []
    for i in range(n):
        r, g, b, _ = struct.unpack_from("<BBBB", d, end - t - 4 * (n - i))
        colors.append(f"{r:02X}{g:02X}{b:02X}")
    return name, colors


def summarize(colors: list[str]) -> str:
    if not colors:
        return "⚠️ unparseable (format drift? update this tool)"
    uniq = sorted(set(colors), key=colors.index)
    if len(uniq) == 1:
        return f"{uniq[0]}  (all {len(colors)} LEDs)"
    return "  ".join(f"{c}×{colors.count(c)}" for c in uniq)


def main() -> int:
    default = pathlib.Path.home() / ".config/OpenRGB/my profile.orp"
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else default
    d = path.read_bytes()
    if not d.startswith(MAGIC):
        print(f"not an OpenRGB profile: {path}", file=sys.stderr)
        return 1
    version = struct.unpack_from("<I", d, len(MAGIC))[0]
    if version not in KNOWN_TAIL:
        print(f"⚠️ format version {version} — this tool was verified on "
              f"{sorted(KNOWN_TAIL)}; check the output against the doc "
              f"table before trusting it", file=sys.stderr)
    print(f"{path}  (format v{version})")
    off = len(MAGIC) + 4
    while off + 4 <= len(d):
        size = struct.unpack_from("<I", d, off)[0]
        if size < 14 or off + size > len(d):
            print(f"  ⚠️ bad block size at offset {off} — stopping", file=sys.stderr)
            return 1
        name, colors = parse_block(d[off:off + size], version)
        print(f"  {name:40s} {summarize(colors)}")
        off += size
    return 0


if __name__ == "__main__":
    sys.exit(main())
