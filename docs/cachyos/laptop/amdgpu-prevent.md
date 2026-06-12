# Laptop: Prevent Apps from Using amdgpu

> ⚠️ **Conflicts with suspend.** "dGPU only" mode pins the panel to NVIDIA and **breaks s2idle suspend** (hang on resume) — see [gpu-mux-suspend.md](gpu-mux-suspend.md). Choose: dGPU-only (apps→NVIDIA, no suspend) **or** Hybrid (suspend works, force NVIDIA per-app with `prime-run`). Currently the FA607PV runs **Hybrid** for working suspend.

Use dGPU only for apps; keep amdgpu loaded for suspend. Set dGPU only in BIOS (counterintuitive but works). Do **not** blacklist amdgpu.

**Remove Mesa VA/Vulkan for iGPU so apps use NVIDIA:** `sudo pacman -R libva-mesa-driver lib32-libva-mesa-driver`; consider removing `vulkan-radeon`. Set `/etc/environment` (NVIDIA/Wayland vars) so Brave/Chrome use NVIDIA. Issues at `brave://gpu` or YouTube may still occur (same on desktop).
