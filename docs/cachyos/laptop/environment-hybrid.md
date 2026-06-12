# Laptop /etc/environment (Hybrid) — proposed, UNTESTED

**Machine:** Laptop (FA607PV).

> ⚠️ **Not applied yet.** Your *live* `/etc/environment` is currently the **desktop's NVIDIA-primary** config (it forces the whole GNOME session onto the dGPU). It works, but in Hybrid mode that keeps the NVIDIA card awake for no reason (heat/battery) instead of letting the AMD iGPU drive the desktop. This is the version to try when you feel like it.

**The idea:** drop the NVIDIA-**primary** block (which forces every app onto NVIDIA) and keep only **PRIME render-offload** — the iGPU drives the desktop, and you opt apps into NVIDIA with `prime-run`.

```ini
## PRIME offload — opt INTO NVIDIA per-app (prime-run <app>); iGPU stays primary
__NV_PRIME_RENDER_OFFLOAD=1
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
__NV_PRIME_RENDER_OFFLOAD_PROVIDER_OPTIONS=0x1
__VK_LAYER_NV_optimus=NVIDIA_only
VK_LAYER_PATH=/usr/share/vulkan/implicit_layer.d

## Wayland (machine-agnostic)
EGL_PLATFORM=wayland
CLUTTER_BACKEND=wayland
GDK_BACKEND=wayland
QT_QPA_PLATFORM=wayland
QT_QPA_PLATFORMTHEME=gtk2
ELECTRON_OZONE_PLATFORM_HINT=auto
ELECTRON_ENABLE_FEATURES=UseOzonePlatform,WaylandWindowDecorations
ELECTRON_OZONE_PLATFORM=wayland
MOZ_ENABLE_WAYLAND=1
WGPU_BACKEND=vulkan

## NVIDIA shader cache (harmless)
__GL_SHADER_DISK_CACHE_SIZE=12000000000
```

**Dropped vs current (the nvidia-primary block):** `GBM_BACKEND=nvidia-drm`, `MESA_LOADER_DRIVER_OVERRIDE=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `VK_ICD_FILENAMES=…nvidia_icd.json`, `VDPAU_DRIVER=nvidia`, `NVD_BACKEND=direct`, `CUDA_VISIBLE_DEVICES=0`. Those force NVIDIA-primary — correct on the desktop, wrong on a Hybrid laptop.

**To use NVIDIA for a game after switching:** `prime-run <cmd>` (from `nvidia-prime`), or in Steam launch options `prime-run %command%`.

**Test safely (only machine — keep a fallback):**
```sh
sudo cp /etc/environment /etc/environment.bak          # backup
sudoedit /etc/environment                              # paste the block above
# log out / reboot
```
**Revert if anything's off:** `sudo cp /etc/environment.bak /etc/environment`, then log out/in. If the GNOME session won't start, switch to a TTY with **Ctrl+Alt+F3**, log in, and revert there.
