# Brave

`brave://flags` — search Wayland and enable both options.

TODO: compare to standard values and possibly remove some.

## Crash in Brave takes GNOME down (Laptop FA607PV)

**Symptom:** Brave's GPU process faults the AMD iGPU and the whole GNOME (Wayland) session drops to GDM with it. First noticed during video, but it also fires with **no video** (e.g. claude.ai chat). Often preceded by ~1–2 s whole-display freezes every ~30 s (the GPU ring soft-recovering) before the fatal reset.

**Two layers, two fixes:**

1. **Cross-GPU decode (older issue).** The iGPU composites the desktop, but Brave's VA-API decoder grabbed the **NVIDIA** node for HW decode; the cross-GPU frame handoff aborted the Mesa compositor. Mitigated by `LIBVA_DRIVER_NAME=radeonsi` in `/etc/environment` (pins decode to the iGPU). Write-up: [laptop/environment-hybrid.md](../laptop/environment-hybrid.md#why-libva_driver_nameradeonsi-brave-hw-video-crash-fix).

2. **iGPU shader permission fault (the one that kept crashing).** Brave's GPU process triggers an amdgpu **gfxhub UTCL2 "SQC (data)" permission page fault** → gfx ring timeout → full GPU reset → session dies. A known Chromium-on-gfx11 bug class, not our config. Disabling only HW *video* decode (`--disable-features=VaapiVideoDecoder`) proved **insufficient** — it faulted again with VA-API off and no video playing — so the **current fix** is to disable Brave's GPU process entirely in `~/.config/brave-flags.conf` (`--disable-gpu`), which supersedes layer 1. If even that doesn't hold, the last resort is handing GNOME compositing back to the dGPU. Full write-up, verification, the desktop-not-affected reasoning, and the firmware red herring: **[laptop/amdgpu-gfx-ring-timeout.md](../laptop/amdgpu-gfx-ring-timeout.md)**.

**Laptop-only** — the desktop hides its AMD APU ([hardware/hide-amd-apu.md](../hardware/hide-amd-apu.md)), so Brave runs on the RTX 5090 there and needs neither fix.
