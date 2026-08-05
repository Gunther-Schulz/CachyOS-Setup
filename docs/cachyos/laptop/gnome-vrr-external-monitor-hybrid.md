# Laptop: GNOME VRR on the external monitor (hybrid GPU)

**Machine:** FA607PV — AMD Raphael iGPU (Ryzen 9 7845HX) + NVIDIA RTX 4060 Mobile, hybrid mode.

**Status:** ❌ VRR is not available on the external monitor under GNOME Wayland. Root cause: the **NVIDIA driver reports the monitor as `vrr_capable=0`** — a driver-level decision with no override path on Wayland. At 330 Hz a divisor-based fps cap is the practical substitute (below).

## Symptom

External monitor — **ASUS XG27JCG**, 2560×1440, Adaptive-Sync **48–330 Hz**, on the **NVIDIA dGPU** (`DP-2`) — has **no VRR toggle** in GNOME Settings → Displays. The internal AMD-driven panel does show one. The **same monitor on the (single-GPU, RTX 5090) desktop** — otherwise identical stack (CachyOS + GNOME + Wayland + NVIDIA) — gets VRR fine.

## Root cause — NVIDIA reports the monitor `vrr_capable=0`

GNOME/Mutter shows the VRR toggle only for outputs whose DRM connector advertises `vrr_capable=1`:

| Connector | Driver | `vrr_capable` |
|---|---|---|
| `DP-2` (external XG27JCG, connected) | NVIDIA | **`0`** |
| `eDP-2` (internal panel, connected) | amdgpu | **`1`** |

```sh
modetest -M nvidia-drm -c | grep -A3 vrr_capable   # value: 0  on the connected DP-2
modetest -M amdgpu    -c | grep -A3 vrr_capable   # value: 1  on the connected eDP-2
```

**Why it reports 0 — leading hypothesis, unverified.** NVIDIA sets `vrr_capable=1` only
for displays it auto-validates as "G-SYNC Compatible" over that link (the manual
override lives in `nvidia-settings`, X11-only; this laptop is Wayland-only). Here the
external display reaches the NVIDIA GPU over **USB-C DP-alt-mode** (no full-size DP on
this chassis) — a link class auto-validation reportedly rejects
([forum thread](https://forums.developer.nvidia.com/t/g-sync-compatible-monitor-not-detected-as-vrr-capable-24g2w1g4/237332),
different monitor). That story was never tested against this monitor, and the reading
has an **uncontrolled confound**: the XG27JCG is dual-mode (5K/180 ↔ 2K/330), and the
monitor's mode and OSD Adaptive-Sync state at read time were not recorded — a monitor
not advertising VRR in its EDID at that moment gets an honest `vrr_capable=0` with
NVIDIA's validation policy playing no part. Recheck parked in
[todo](../todo.md) with the controlled battery.

Ruled out (don't re-investigate): Mutter primary GPU (no effect — see below), GDM-on-X11 (greeter runs Wayland here), non-atomic KMS (both GPUs use atomic), and driver/hardware capability (Ada + a current NVIDIA driver clears the ≥Volta / ≥525 Wayland-VRR floor).

## Practical substitute — divisor cap at 330 Hz

VRR is low-value at 330 Hz anyway (~3 ms refresh granularity), so a fixed cap that cleanly divides the refresh gives flat frametimes without it: **110** (330/3) or **165** (330/2), set in MangoHud (`fps_limit`). See the Marvel Rivals / MangoHud notes.

## Mutter primary GPU

Mutter composites on the **NVIDIA dGPU**, not the default AMD iGPU — a udev rule applied for an unrelated reason (it fixes an Electron/Chromium GPU-reset crash that only happened while the iGPU composited). It has **no effect on VRR** (confirmed above: the block is in the NVIDIA driver, not the compositor). See [amdgpu-gfx-ring-timeout.md](amdgpu-gfx-ring-timeout.md) for the rule, why it's applied, and how to switch back.

## Related

- [`gpu-mux-suspend.md`](gpu-mux-suspend.md) — dGPU-only mode (which would make NVIDIA the sole GPU) is off the table: it breaks s2idle suspend.
- [`amdgpu-gfx-ring-timeout.md`](amdgpu-gfx-ring-timeout.md) — the Mutter-primary-GPU udev rule, applied for the iGPU crash, not for VRR.
