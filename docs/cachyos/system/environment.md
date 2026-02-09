# Environment (NVIDIA / Wayland)

Add to `/etc/environment` (or equivalent). Use for NVIDIA-only or PRIME offload setups.

```ini
## NVIDIA
__GLX_VENDOR_LIBRARY_NAME=nvidia
MESA_LOADER_DRIVER_OVERRIDE=nvidia
VDPAU_DRIVER=nvidia
GBM_BACKEND=nvidia-drm
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
NVD_BACKEND=direct

## PRIME offload (laptop)
__NV_PRIME_RENDER_OFFLOAD=1
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
__NV_PRIME_RENDER_OFFLOAD_PROVIDER_OPTIONS=0x1
CUDA_VISIBLE_DEVICES=0

## Wayland
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

## Vulkan
VK_LAYER_PATH=/usr/share/vulkan/implicit_layer.d
__VK_LAYER_NV_optimus=NVIDIA_only

## Shader cache (optional)
__GL_SHADER_DISK_CACHE_SIZE=12000000000
```

**Troubleshooting GNOME:** `export GSK_RENDERER=cairo` to disable GPU rendering.
