# Todo

- Use Limine bootloader on the laptop (automatic snapshots supported).
- Compare Brave Wayland flags to standard values; possibly remove some.
- **Desktop:** confirm the PowerMizer max-perf autostart is removed and PowerMizer is back to default (`nvidia-settings -q [gpu:0]/GpuPowerMizerMode`).
- **Desktop:** enlarge the `/boot` partition so more Limine snapshots fit — see [recovery/boot-part-enlarge.md](recovery/boot-part-enlarge.md).
- **Desktop:** verify + remove the now-unneeded GNOME screencast workaround — the VA-API blocklist autostart (`~/.config/autostart/gnome-screencast-vaapi-blocklist.desktop`) **and** the `GST_PLUGIN_FEATURE_RANK` line in `/etc/environment` (recording works fine without them on the laptop; test the recorder on the desktop, then delete both).
