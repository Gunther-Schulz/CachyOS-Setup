# Laptop /etc/environment (Hybrid)

**Machine:** Laptop (FA607PV).

> ✅ **Applied.** The AMD iGPU drives the desktop; NVIDIA is opt-in per app via `prime-run <cmd>`. The old NVIDIA-primary version is backed up at `/etc/environment.bak`.

**The idea:** no NVIDIA-**primary** block (which would force every app onto the dGPU). Keep only **PRIME render-offload** — the iGPU drives the desktop and composites, and you opt apps into NVIDIA with `prime-run`. VA-API video decode is pinned to the iGPU so it stays on the same GPU as the compositor (see below).

```ini
## PRIME offload — opt INTO NVIDIA per-app (prime-run <app>); iGPU stays primary
__NV_PRIME_RENDER_OFFLOAD=1
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
__NV_PRIME_RENDER_OFFLOAD_PROVIDER_OPTIONS=0x1
__VK_LAYER_NV_optimus=NVIDIA_only
VK_LAYER_PATH=/usr/share/vulkan/implicit_layer.d

## VA-API HW video decode → pin to AMD iGPU (same GPU as the compositor).
## Prevents the cross-GPU crash described below.
LIBVA_DRIVER_NAME=radeonsi

## Wayland (machine-agnostic)
EGL_PLATFORM=wayland
WGPU_BACKEND=vulkan
CLUTTER_BACKEND=wayland
GDK_BACKEND=wayland
QT_QPA_PLATFORM=wayland
QT_QPA_PLATFORMTHEME=gtk2
ELECTRON_OZONE_PLATFORM_HINT=auto
ELECTRON_ENABLE_FEATURES=UseOzonePlatform,WaylandWindowDecorations
ELECTRON_OZONE_PLATFORM=wayland
MOZ_ENABLE_WAYLAND=1

## NVIDIA shader cache (harmless)
__GL_SHADER_DISK_CACHE_SIZE=12000000000
```

**Dropped vs the old nvidia-primary block:** `GBM_BACKEND=nvidia-drm`, `MESA_LOADER_DRIVER_OVERRIDE=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `VK_ICD_FILENAMES=…nvidia_icd.json`, `VDPAU_DRIVER=nvidia`, `NVD_BACKEND=direct`, `CUDA_VISIBLE_DEVICES=0`. Those force NVIDIA-primary — correct on the desktop, wrong on a Hybrid laptop.

**To use NVIDIA for a game:** `prime-run <cmd>` (from `nvidia-prime`), or in Steam launch options `prime-run %command%`.

## Why `LIBVA_DRIVER_NAME=radeonsi` (Brave HW-video crash fix)

Without it, browsers/players auto-pick the **NVIDIA** render node (`renderD128`, via `libva-nvidia-driver`/NVDEC) for hardware video decode — even though `mutter` composites on the **AMD iGPU** (`renderD129`). Every decoded frame then takes a cross-GPU dmabuf + explicit-sync-fence handoff from NVIDIA → AMD. That fragile path intermittently logs `nvidia_drm … sync FD semaphore surface` faults and makes the **Mesa compositor `abort()` mid-swap** (`dri_flush` inside `cogl_onscreen_swap_buffers_with_damage`) — which on Wayland takes the **entire GNOME session** down. It only manifests during HW video, because that's the only thing that touched the NVIDIA node.

Pinning VA-API to `radeonsi` keeps decode + render + composite all on the iGPU, so nothing crosses the GPU boundary. The iGPU's `radeonsi` VA-API supports H264 / HEVC / VP9 / AV1, so hardware decode is retained, not lost.

**Verify** (after login, with a video playing in Brave):

```sh
# Brave's GPU process should hold ONLY the iGPU node, not renderD128 (NVIDIA):
for p in $(pgrep -f 'type=gpu-process'); do ls -l /proc/$p/fd 2>/dev/null | grep -o 'renderD12[89]'; done | sort -u
# brave://gpu → "Video Decode" should still read "Hardware accelerated"
```

**To deliberately use NVDEC for one app** (rare): `LIBVA_DRIVER_NAME=nvidia prime-run <cmd>`.

## Apply / revert

The config block above is the canonical copy — recreate `/etc/environment` from it if needed. Before any future edit, back up first:

```sh
sudo cp /etc/environment /etc/environment.bak.$(date +%F)   # timestamped backup
sudoedit /etc/environment                                   # edit, then log out / reboot
```

If a bad edit breaks the GNOME session, switch to a TTY with **Ctrl+Alt+F3**, log in, and fix it there. `/etc/environment.bak` holds the older NVIDIA-primary version for a full fallback.
