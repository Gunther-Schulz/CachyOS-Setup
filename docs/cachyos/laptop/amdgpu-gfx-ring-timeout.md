# Laptop: amdgpu iGPU gfx ring timeout → GNOME/Wayland session dies

**Machine:** Laptop (FA607PV) — Radeon iGPU (Raphael, Ryzen 9 7845HX)

**Status:** 🧪 **In testing** since 2026-06-21 — mitigation applied, watching for recurrence.

## Symptom

Whole GNOME session drops to GDM (looks like the machine "crashed"), but the system stays up — **no reboot**, uptime keeps counting. On Wayland a `gnome-shell` crash tears down the entire session, which is why it feels total. GDM restarts the shell ~12s later.

## Root cause

The **AMD integrated GPU** (`0000:05:00.0`, Raphael) stalls on a render command. Kernel resets the GPU; when the soft ring-reset fails it escalates to a full GPU reset, and the lost GPU context makes Mesa (`libgallium`) `abort()` mid buffer-swap, taking `gnome-shell` with it. The **NVIDIA dGPU is not involved**.

Kernel fingerprint (persists in journal across boots even after coredumps rotate out):

```
amdgpu 0000:05:00.0: ring gfx_0.1.0 timeout, signaled seq=N, emitted seq=N+2
amdgpu 0000:05:00.0: Ring gfx_0.1.0 reset failed
amdgpu 0000:05:00.0: GPU reset begin!
amdgpu 0000:05:00.0: [drm] device wedged, but recovered through reset
```

Mesa side, from `coredumpctl info <pid>` on `gnome-shell`:

```
abort (libc) → libgallium-26.1.2 → dri_flush → libEGL_mesa
→ cogl_onscreen_swap_buffers_with_damage (libmutter-cogl) → … (SIGABRT)
```

Each hang has the same signature: `emitted seq` exactly **2 ahead** of `signaled seq` (a stuck render command). **Not** correlated with suspend/resume — observed spontaneously under normal light load.

Observed 2026-06-21 (journal only retains ~3 days, so earlier occurrences already rotated out):
- 13:54 — `gfx_0.0.0` timeout, soft ring-reset **succeeded**, session survived (Brave took the hit).
- 17:54 — `gfx_0.1.0` timeout, soft reset **failed** → full GPU reset → killed `gnome-shell`.

Environment at time of hangs: `linux-cachyos 7.0.12`, `mesa 2:26.1.2` (both bleeding-edge).

## Mitigation under test — disable PSR (Panel Self-Refresh)

PSR is the most common cause of this exact signature (spontaneous `gfx` ring timeout, light load, no suspend correlation) on Raphael/Phoenix laptop iGPUs. Add the kernel parameter via GRUB:

```sh
# /etc/default/grub — append inside GRUB_CMDLINE_LINUX_DEFAULT='...'
amdgpu.dcdebugmask=0x10

sudo grub-mkconfig -o /boot/grub/grub.cfg
# reboot
```

Verify it took:

```sh
grep -o 'amdgpu.dcdebugmask=[^ ]*' /proc/cmdline   # → amdgpu.dcdebugmask=0x10
```

**Success criterion:** after a few days of normal use this stays empty:

```sh
journalctl -k | grep -iE "ring .*timeout|device wedged"
```

## Fallback if it still hangs

1. **Isolate kernel vs Mesa** — boot the already-installed `linux-cachyos-lts` (6.18.x) from the GRUB menu and run on it a few days. Stable on LTS ⇒ amdgpu regression in the 7.0 kernel; stay on LTS until fixed upstream.
2. **memtest** — the iGPU uses system RAM as VRAM, so flaky RAM surfaces as GPU hangs. `memtest86+` overnight. Lower priority; only if 1 doesn't resolve it.
3. Report upstream at gitlab.freedesktop.org/drm/amd with the devcoredump — but only after the PSR test, since PSR-disable resolving it is more informative than a raw dump.
