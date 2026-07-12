# GNOME

**Performance patches:** `yay -S gnome-shell-performance` (or mutter-performance as referenced in source).

**Fractional scaling and G-Sync:** Both can be enabled together (GNOME 49+):
```bash
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'variable-refresh-rate']"
```
Reboot. Test G-Sync: `yay -S gl-gsync-demo`.

If issues occur, use only one: fractional scaling `['scale-monitor-framebuffer']` or G-Sync `['variable-refresh-rate']`.

**Extensions:** `sudo pacman -S gnome-shell-extensions gnome-browser-connector`, then install from [extensions.gnome.org](https://extensions.gnome.org) (or the Extension Manager app). Enabled:

| Extension | Purpose |
|---|---|
| Dash to Dock | persistent dock |
| Just Perfection | granular shell UI tweaks |
| Custom Hot Corners – Extended | corner/edge actions |
| AppIndicator / KStatusNotifier Support | legacy tray icons |
| Astra Monitor | system-resource readout in the top bar |
| Caffeine | inhibit auto-suspend/screensaver on demand |
| Solaar Extension | Logitech device status (pairs with `solaar`) |
| User Themes | custom shell theme (bundled in `gnome-shell-extensions`) |
| Always Show Titles in Overview | window titles in the overview |
| Respect Do Not Disturb | honor DND |
| Sleep Through Notifications | suppress wake-on-notification |

**Hide window shortcut:** Settings → Keyboard → Windows → Hide window (default Super+H).

**Screen recorder:** the built-in GNOME recorder (`Ctrl+Shift+Alt+R`) works fine on the laptop (GNOME 50 + nvidia-open 610) with no workaround. It *used* to produce corrupt video on older NVIDIA Wayland — which needed a VA-API-pipeline blocklist (login autostart) plus a `GST_PLUGIN_FEATURE_RANK` encoder demote — now unnecessary. If it misbehaves on the **desktop** (RTX 5090), that's a config difference or a Blackwell-specific issue, not a general bug; the old workaround is in git history.
