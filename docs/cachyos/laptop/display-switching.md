# Display Switching (laptop + external monitor)

Two scripts toggle between using only the external monitor vs. extending across both. They talk to GNOME/Mutter over D-Bus (`org.gnome.Mutter.DisplayConfig`) and re-read the live state each run (resolution, scale, config serial) — nothing hard-coded, so they survive resolution/scale changes. **GNOME/Wayland session required.**

| Script | Effect |
|--------|--------|
| `~/display-solo` | External monitor **only**; built-in laptop panel **off**. |
| `~/display-both` | **Extend** across both (external primary, laptop panel placed to its right). |

**Managed by dotfiles** (`dotfiles/laptop/`, laptop-scoped). Deploy with `~/dev/Gunther-Schulz/dotfiles/dot apply`.

**Use:** `~/display-solo` / `~/display-both`. Each prints what it applied (e.g. `✓ External only: DP-2 @ 2560x1440@…`).
