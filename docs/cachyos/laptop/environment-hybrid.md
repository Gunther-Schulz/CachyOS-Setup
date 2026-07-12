# Laptop /etc/environment (Hybrid)

**Machine:** Laptop (FA607PV).

> ✅ **Applied.** This file keeps **PRIME render-offload** env (no global NVIDIA-primary block); NVIDIA is opt-in per app via `prime-run <cmd>`. The old NVIDIA-primary version is backed up at `/etc/environment.bak`.
>
> ⚠️ **2026-06-30:** GNOME compositing was moved onto the **NVIDIA dGPU** by a *separate* mechanism — the [Mutter-primary udev rule](amdgpu-gfx-ring-timeout.md) — to fix the [iGPU Electron/Chromium crash](amdgpu-gfx-ring-timeout.md). That doesn't change this file's PRIME-offload design, but it **flips `LIBVA_DRIVER_NAME` from `radeonsi` → `nvidia`** so HW decode follows the compositor (see below).

**The idea:** no NVIDIA-**primary** block (which would force *every* app onto the dGPU at the env level). Keep only **PRIME render-offload** — apps default to the iGPU node unless opted into NVIDIA with `prime-run`. (Compositing itself is steered separately by the Mutter-primary udev rule, now on the dGPU.) VA-API video decode is pinned to whichever GPU composites the desktop — now the NVIDIA dGPU (see below).

```ini
## PRIME offload — opt INTO NVIDIA per-app (prime-run <app>); iGPU stays primary
__NV_PRIME_RENDER_OFFLOAD=1
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
__NV_PRIME_RENDER_OFFLOAD_PROVIDER_OPTIONS=0x1
__VK_LAYER_NV_optimus=NVIDIA_only
VK_LAYER_PATH=/usr/share/vulkan/implicit_layer.d

## VA-API HW video decode → pin to the GPU that composites the desktop.
## Compositor is now the NVIDIA dGPU (Mutter-primary udev rule), so decode = nvidia
## (NVDEC via libva-nvidia-driver). Prevents the cross-GPU handoff described below.
## If you ever revert compositing back to the iGPU, set this back to radeonsi.
LIBVA_DRIVER_NAME=nvidia

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

## Why `LIBVA_DRIVER_NAME` follows the compositor

VA-API video decode must land on the **same GPU that composites the desktop**, or every decoded frame takes a cross-GPU dmabuf + explicit-sync-fence handoff. That fragile path intermittently logs `nvidia_drm … sync FD semaphore surface` faults and makes the compositor **`abort()` mid-swap** (`dri_flush` inside `cogl_onscreen_swap_buffers_with_damage`) — which on Wayland takes the **entire GNOME session** down. It only manifests during HW video, because that's the only thing that crosses the GPU boundary.

The rule is just **decode on the compositor's GPU**, so the right value tracks which GPU Mutter composites on:

- **Compositor on the iGPU** (old default) → `LIBVA_DRIVER_NAME=radeonsi`. Without it, browsers auto-picked the NVIDIA node (`renderD128`, NVDEC) while Mutter composited on the AMD iGPU (`renderD129`) → cross-GPU crash.
- **Compositor on the NVIDIA dGPU** (current, since 2026-06-30 — [amdgpu-gfx-ring-timeout.md](amdgpu-gfx-ring-timeout.md)) → **`LIBVA_DRIVER_NAME=nvidia`** (NVDEC via `libva-nvidia-driver`, installed). Now `radeonsi` would be the cross-GPU one.

Both NVDEC and `radeonsi` cover H264 / HEVC / VP9 / AV1, so hardware decode is retained either way, not lost.

**Verify** (after login, with a video playing in Brave):

```sh
# Brave's GPU process should hold the compositor's node — on NVIDIA primary that's renderD128:
for p in $(pgrep -f 'type=gpu-process'); do ls -l /proc/$p/fd 2>/dev/null | grep -o 'renderD12[89]'; done | sort -u
# brave://gpu → "Video Decode" should still read "Hardware accelerated"
```

**If NVDEC misbehaves** (Chromium + nvidia-vaapi can be fussy): video may fall back to CPU decode (fine on the 7845HX) or glitch. Then accept CPU decode, or revert compositing to the iGPU and set `radeonsi` again. **To force the iGPU decoder for one app:** `LIBVA_DRIVER_NAME=radeonsi <cmd>`.

## Apply / revert

The config block above is the canonical copy — recreate `/etc/environment` from it if needed. Before any future edit, back up first:

```sh
sudo cp /etc/environment /etc/environment.bak.$(date +%F)   # timestamped backup
sudoedit /etc/environment                                   # edit, then log out / reboot
```

If a bad edit breaks the GNOME session, switch to a TTY with **Ctrl+Alt+F3**, log in, and fix it there. `/etc/environment.bak` holds the older NVIDIA-primary version for a full fallback.
