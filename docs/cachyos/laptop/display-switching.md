# Display Switching (laptop + external monitor)

Two scripts toggle between using only the external monitor vs. extending across both. They talk to GNOME/Mutter over D-Bus (`org.gnome.Mutter.DisplayConfig`) and re-read the live state each run (resolution, scale, config serial) — nothing hard-coded, so they survive resolution/scale changes. **GNOME/Wayland session required.**

| Script | Effect |
|--------|--------|
| [`scripts/display-solo`](scripts/display-solo) | External monitor **only**; built-in laptop panel **off**. |
| [`scripts/display-both`](scripts/display-both) | **Extend** across both (external primary, laptop panel placed to its right). |

**Install** (they live in `~/`):
```sh
cp docs/cachyos/laptop/scripts/display-solo docs/cachyos/laptop/scripts/display-both ~/
chmod +x ~/display-solo ~/display-both
```

**Use:** `~/display-solo` / `~/display-both`. Each prints what it applied (e.g. `✓ External only: DP-2 @ 2560x1440@…`).

Canonical copies are versioned in `scripts/` here; `~/` holds the working copies.
