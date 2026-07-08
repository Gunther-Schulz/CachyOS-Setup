# NVIDIA open kernel modules (and switching driver branches)

NVIDIA is **sunsetting the proprietary (closed) kernel modules** upstream — the **open kernel modules** are the maintained path for Turing+ (RTX 20-series and newer). Important: "open kernel modules" ≠ "open driver". Only the **kernel modules** are open (MIT/GPL); the **userspace** (Vulkan / GL / EGL / CUDA, and the Wayland present path) is still closed NVIDIA. Only **nouveau / NVK** is fully open — not viable for modern gaming.

| Stack | Kernel modules | Userspace |
|---|---|---|
| nouveau / NVK | open | open (Mesa) |
| **`nvidia-open-dkms`** | **open** (MIT/GPL) | closed NVIDIA |
| `nvidia-dkms` / `nvidia-*xx-dkms` (closed) | closed | closed NVIDIA |

**Blackwell (RTX 50-series) is open-only** — the closed modules don't support it at all, so the desktop 5090 is necessarily on `nvidia-open-dkms`.

## Which am I on?

```sh
modinfo -F license nvidia       # "Dual MIT/GPL" = open modules; "NVIDIA" = closed  (definitive)
cat /sys/module/nvidia/version  # the LOADED driver version — only changes after a reboot
pacman -Q | grep -E 'nvidia-(open-)?dkms'
```
Note the loaded version lags a package swap until you reboot — after switching you'll briefly see the new module *on disk* (`modinfo`) but the old one *loaded* (`/sys/module`).

## The whole stack must move together — and versions must match

The kernel module and the userspace **must be the same version**. A 610 module with 580 utils = **black screen on reboot**. So switching branches means replacing the *entire* stack:

| From (closed / `580xx` legacy branch) | To (mainline open) |
|---|---|
| `nvidia-580xx-dkms` | `nvidia-open-dkms` |
| `nvidia-580xx-utils` | `nvidia-utils` |
| `lib32-nvidia-580xx-utils` | `lib32-nvidia-utils` |
| `opencl-nvidia-580xx` | `opencl-nvidia` |
| `lib32-opencl-nvidia-580xx` | `lib32-opencl-nvidia` |

`nvidia-settings`, `libva-nvidia-driver`, `linux-firmware-nvidia` are version-independent — no change.

**Switch (all in one transaction):**
```sh
sudo pacman -S nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia
#   → confirm removal of the conflicting *-580xx-* packages
pacman -Q | grep -iE 'nvidia|opencl-nvidia'   # verify: ALL the same version, NO 580xx left
sudo reboot
```
No `mkinitcpio` needed — nvidia isn't in the initramfs here (`MODULES=(crc32c)`). Dependents (steam, proton-cachyos-slr, zed…) require the virtual `nvidia-utils`, which the mainline package provides, so nothing breaks. Verify after reboot: `modinfo -F license nvidia` → `Dual MIT/GPL`; `cat /sys/module/nvidia/version` → the new version.

**⚠️ Never reboot mid-swap** (610 module + 580 utils). If you installed `nvidia-open-dkms` first, finish the utils before rebooting.

**Rollback if black screen** (TTY = Ctrl+Alt+F3):
```sh
sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils opencl-nvidia-580xx lib32-opencl-nvidia-580xx
sudo reboot
```

## Module settings survive the switch (`/etc/modprobe.d/`)

Module options use the same names (`nvidia`, `nvidia-drm`) on open and closed, so they carry over unchanged — **no edits needed** to switch. On the laptop:

- **`nvidia.conf`** — keep the two suspend options:
  - `NVreg_PreserveVideoMemoryAllocations=1` — VRAM save/restore across suspend (stops s2idle from corrupting VRAM). Not default → keep.
  - `NVreg_EnableS0ixPowerManagement=1` — s2idle GPU power management. Not default → keep.
  - `nvidia-drm modeset=1` — **default-on since driver 545+**, now redundant (harmless).
  - `fbdev` / `NVreg_DynamicPowerManagement` — left commented (`fbdev` defaults to `1`, good for Wayland; DynamicPM is moot since the dGPU composites the desktop and never runtime-suspends).
- **`supergfxd.conf`** — `blacklist nouveau` (keep) + `nvidia-drm modeset=1` (redundant, harmless).

## Machine status

- **Laptop (FA607PV, RTX 4060 Ada):** was on the **closed** `nvidia-580xx-dkms` — a legacy branch deliberately chosen 2025-12-18 (no `IgnorePkg` pin, just the installed package). Switched to **`nvidia-open-dkms` 610.43.02 (open)** on **2026-07-08** — confirmed on reboot (`modinfo` → `Dual MIT/GPL`, banner "Open Kernel Module", GPU healthy). Because the `580xx` branch was likely a stability choice against a newer-driver regression, if 610 misbehaves, roll back to the `580xx` closed stack per above. **Bonus outcome:** 610 brought a **~20 fps gain** in Marvel Rivals over the frozen 580 branch — a pinned/legacy driver silently costs the accumulated shader-compiler and Vulkan optimizations. No regressions seen.
- **Desktop (RTX 5090 Blackwell):** open-only by hardware requirement.
