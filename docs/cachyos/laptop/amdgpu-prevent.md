# Laptop: Prevent Apps from Using amdgpu

Use dGPU only for apps; keep amdgpu loaded for suspend. Set dGPU only in BIOS (counterintuitive but works). Do **not** blacklist amdgpu.

**Remove Mesa VA/Vulkan for iGPU so apps use NVIDIA:** `sudo pacman -R libva-mesa-driver lib32-libva-mesa-driver`; consider removing `vulkan-radeon`. Set `/etc/environment` (NVIDIA/Wayland vars) so Brave/Chrome use NVIDIA. Issues at `brave://gpu` or YouTube may still occur (same on desktop).
