# Brave

`brave://flags` — search Wayland and enable both options.

TODO: compare to standard values and possibly remove some.

## Crash during HW-accelerated video takes GNOME down (Laptop FA607PV)

**Symptom:** intermittent — Brave crashes while playing hardware-accelerated video and the whole GNOME (Wayland) session dies with it.

**Cause:** on the Hybrid laptop the iGPU composites the desktop, but Brave's VA-API decoder was grabbing the **NVIDIA** node for HW video decode. The cross-GPU frame handoff aborts the Mesa compositor. Full write-up + verification steps: [laptop/environment-hybrid.md](../laptop/environment-hybrid.md#why-libva_driver_nameradeonsi-brave-hw-video-crash-fix).

**Fix:** `LIBVA_DRIVER_NAME=radeonsi` in `/etc/environment` (pins VA-API to the iGPU). HW decode is kept, not disabled.
