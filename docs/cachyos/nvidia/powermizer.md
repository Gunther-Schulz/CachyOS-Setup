# NVIDIA PowerMizer — Choppy Mouse at Low/Transitioning GPU Load

**Symptoms:** Mouse (and sometimes display) choppy when GPU is at low or changing load; smooth at full idle or high load.

**Cause:** PowerMizer switches P-states; transitions can stall the Wayland compositor.

**Fix:** Prefer maximum performance (slightly higher idle power).

**One-time test:**
```bash
nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1"
```

**Permanent (autostart):**
```bash
mkdir -p ~/.config/autostart
cat << 'EOF' > ~/.config/autostart/nvidia-powermizer-maxperf.desktop
[Desktop Entry]
Type=Application
Name=NVIDIA PowerMizer maximum performance
Exec=sh -c "nvidia-settings -a [gpu:0]/GpuPowerMizerMode=1"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
```
Log out and back in. Use `[gpu:0]` literally in `Exec`.

**Verify:** `nvidia-settings -q [gpu:0]/GpuPowerMizerMode` → `1`.
