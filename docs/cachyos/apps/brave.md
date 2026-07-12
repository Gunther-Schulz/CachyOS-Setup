# Brave

**Machine:** Laptop (FA607PV).

`brave://flags` — search Wayland and enable both options.

## GPU-process crash takes down the whole GNOME session

A Chromium GPU-process bug on gfx11 AMD iGPUs (not Brave-specific — every Electron/Chromium app on this iGPU is exposed, confirmed byte-identical in Claude Desktop) can crash the GPU process and take the whole GNOME (Wayland) session down with it. Fixed at the compositor level, not per-app: GNOME composites on the NVIDIA dGPU, so Chromium renders there and the faulting iGPU path is never hit. Brave runs with full GPU acceleration (no `--disable-gpu` needed). Root cause, fix, and verification: [laptop/amdgpu-gfx-ring-timeout.md](../laptop/amdgpu-gfx-ring-timeout.md).

**VA-API decode** follows the compositor onto the dGPU — `LIBVA_DRIVER_NAME=nvidia` (see [laptop/environment-hybrid.md](../laptop/environment-hybrid.md#why-libva_driver_name-follows-the-compositor)).

**Laptop-only** — the desktop hides its AMD APU ([hardware/hide-amd-apu.md](../hardware/hide-amd-apu.md)); Brave runs on the RTX 5090 there.
