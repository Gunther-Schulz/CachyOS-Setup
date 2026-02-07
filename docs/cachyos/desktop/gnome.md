# GNOME

**Performance patches:** `yay -S gnome-shell-performance` (or mutter-performance as referenced in source).

**Fix crashes/glitches (GPU acceleration):** Add to `/etc/environment`:
```bash
export GSK_RENDERER=cairo
```

**Fractional scaling vs G-Sync:** Only one at a time. Fractional scaling:
```bash
gsettings set org.gnome.mutter experimental-features '["scale-monitor-framebuffer"]'
```
Reboot. G-Sync:
```bash
gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']"
```
Restart session. Test: `yay -S gl-gsync-demo`.

**Extensions:** `sudo pacman -S gnome-shell-extensions gnome-browser-connector`. Extensions list: Astra, etc. (TODO: add knotifier).

**Hide window shortcut:** Settings → Keyboard → Windows → Hide window (default Super+H).
