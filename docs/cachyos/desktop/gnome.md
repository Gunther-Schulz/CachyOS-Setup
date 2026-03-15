# GNOME

**Performance patches:** `yay -S gnome-shell-performance` (or mutter-performance as referenced in source).

**Fix crashes/glitches (GPU acceleration):** Add to `/etc/environment`:
```bash
export GSK_RENDERER=cairo
```

**Fractional scaling and G-Sync:** Both can be enabled together (GNOME 49+):
```bash
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'variable-refresh-rate']"
```
Reboot. Test G-Sync: `yay -S gl-gsync-demo`.

If issues occur, use only one: fractional scaling `['scale-monitor-framebuffer']` or G-Sync `['variable-refresh-rate']`.

**Extensions:** `sudo pacman -S gnome-shell-extensions gnome-browser-connector`. Extensions list: Astra, etc. (TODO: add knotifier).

**Hide window shortcut:** Settings → Keyboard → Windows → Hide window (default Super+H).

**Screen recorder (partial fix):** The built-in GNOME screen recorder (Ctrl+Shift+Alt+R) produces corrupt videos by default on NVIDIA Wayland — wrong resolution, 0 fps, multi-hour bogus duration. Root causes: `nvh264enc` registers at GStreamer rank 257 (beats all software encoders), and GNOME's VA-API pipelines silently misbehave against NVIDIA's decode-only VA-API driver.

The `GST_PLUGIN_FEATURE_RANK` fix in `system/environment.md` demotes the NVIDIA GStreamer encoders. The VA-API pipelines are blocked via an autostart entry that writes GNOME's pipeline blocklist at login:

Create `~/.config/autostart/gnome-screencast-vaapi-blocklist.desktop`:
```ini
[Desktop Entry]
Type=Application
Name=Block broken VA-API screencast pipelines
Exec=sh -c 'echo "[\"hwenc-dmabuf-h264-vaapi-lp\",\"hwenc-dmabuf-h264-vaapi\"]" > /run/user/1000/gnome-shell-screencast-pipeline-blocklist'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
```

**Caveat:** Recording works and plays back correctly, but the video file duration metadata is wrong (shows hours instead of seconds). This is a GStreamer/PipeWire timestamp overflow bug on NVIDIA Wayland with fractional scaling enabled — unfixed upstream. Fix individual recordings with:
```bash
ffmpeg -i "input.mp4" -c copy "fixed.mp4"
```
