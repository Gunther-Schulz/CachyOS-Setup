# Brave

`brave://flags` — search Wayland and enable both options.

TODO: compare to standard values and possibly remove some.

## Crash in Brave (and any Electron app) takes GNOME down (Laptop FA607PV)

**Symptom:** a Chromium GPU process faults the AMD iGPU and the whole GNOME (Wayland) session drops to GDM with it. First noticed in Brave during video, but it also fires with **no video** (e.g. claude.ai chat). Often preceded by ~1–2 s whole-display freezes every ~30 s (the GPU ring soft-recovering) before the fatal reset.

**It's not a Brave bug** — it's a **Chromium/Electron GPU-process bug on the gfx11 AMD iGPU**, shared by every Chromium-based app. The **Claude Desktop** Electron app tripped the byte-for-byte identical fault on 2026-06-30 with Brave not even running. So the fix is systemic, not per-app.

**Fix (applied 2026-06-30): composite on the NVIDIA dGPU, not the iGPU.** A Mutter-primary udev rule moves GNOME compositing onto the dGPU (staying Hybrid, so suspend still works); Chromium then auto-renders on the dGPU and the iGPU never sees the faulting submission — for Brave **and every other Electron app at once**. Brave runs with **full GPU acceleration again** (the old `--disable-gpu` workaround was reverted). Full write-up, verification, the firmware red herring, and the per-app `--disable-gpu` stopgap: **[laptop/amdgpu-gfx-ring-timeout.md](../laptop/amdgpu-gfx-ring-timeout.md)**.

**Older, separate layer — cross-GPU decode.** Before the compositing switch, with the *iGPU* compositing, Brave's VA-API decoder grabbing the NVIDIA node caused a cross-GPU handoff that aborted the Mesa compositor — which is why decode used to be pinned to the iGPU (`LIBVA_DRIVER_NAME=radeonsi`). Now the compositor is the dGPU, so decode is pinned to **`nvidia`** to match — same principle (decode on the compositor's GPU): [laptop/environment-hybrid.md](../laptop/environment-hybrid.md#why-libva_driver_name-follows-the-compositor).

**Laptop-only** — the desktop hides its AMD APU ([hardware/hide-amd-apu.md](../hardware/hide-amd-apu.md)), so Brave runs on the RTX 5090 there and needs none of this.
