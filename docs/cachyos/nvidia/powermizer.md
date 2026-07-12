# NVIDIA PowerMizer — Choppy Mouse at Low/Transitioning GPU Load

**Machine:** Desktop.

**Symptom:** Mouse (and sometimes display) choppy when the GPU is at low or changing load; smooth at full idle or high load. **Cause:** PowerMizer P-state transitions can stall the Wayland compositor.

**Keep PowerMizer at default — do not set anything custom.** Forcing max performance (`GpuPowerMizerMode=1` via a login autostart) was tried and **did nothing** when tested — likely a no-op on Wayland + the RTX 5090.

**TODO (desktop):** confirm the old `~/.config/autostart/nvidia-powermizer-maxperf.desktop` is removed and PowerMizer reads default — `nvidia-settings -q [gpu:0]/GpuPowerMizerMode`.
