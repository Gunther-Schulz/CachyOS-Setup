# Laptop: GNOME VRR on the external monitor (hybrid GPU)

**Machine:** FA607PV — AMD Raphael iGPU (Ryzen 9 7845HX) + NVIDIA RTX 4060 Mobile, hybrid mode (`supergfxctl` = Hybrid).

**Status:** ❌ **VRR is not available on the external monitor under GNOME Wayland (2026-06-23).** Root cause: the **NVIDIA driver reports the monitor as `vrr_capable=0`** — a driver-level decision with no override path on Wayland. *Not* a Mutter / primary-GPU / compositor-config issue (all ruled out below). At 330 Hz a divisor cap is the practical substitute.

## Symptom

External monitor — **ASUS XG27JCG**, 2560×1440, Adaptive-Sync **48–330 Hz**, on the **NVIDIA dGPU** (`DP-2`) — has **no VRR toggle** in GNOME Settings → Displays. The internal AMD-driven panel does show one. The **same monitor on the (single-GPU, RTX 5090) desktop** — otherwise identical stack: CachyOS + GNOME 50 + Wayland + NVIDIA 580 — gets VRR fine.

## Root cause — NVIDIA reports the monitor `vrr_capable=0`

GNOME/Mutter shows the VRR toggle only for outputs whose DRM connector advertises `vrr_capable=1`. Dumping the live connector properties shows the NVIDIA driver flags the external monitor **not** capable, while amdgpu flags the internal panel capable:

| Connector | Driver | `vrr_capable` |
|---|---|---|
| `DP-2` (external XG27JCG, connected) | NVIDIA | **`0`** |
| `eDP-2` (internal panel, connected) | amdgpu | **`1`** |

```sh
modetest -M nvidia-drm -c | grep -A3 vrr_capable   # value: 0  on the connected DP-2
modetest -M amdgpu    -c | grep -A3 vrr_capable   # value: 1  on the connected eDP-2
```

The block is **in the NVIDIA driver, below the compositor.** NVIDIA sets `vrr_capable=1` only for a display it has **auto-validated as "G-SYNC Compatible"** over that specific link, or where the user has manually ticked *"Allow G-SYNC on a monitor not validated as G-SYNC Compatible."* This monitor isn't getting that flag on the laptop. amdgpu instead flags any EDID-advertised FreeSync panel capable — hence the internal toggle.

### Why it works on the desktop but not the laptop (same monitor)

`vrr_capable` is decided per **display + connection + GPU**, not per monitor model:

- **Desktop:** monitor on a **native DisplayPort** straight off the GPU → NVIDIA auto-validates G-SYNC Compatible → `vrr_capable=1`.
- **Laptop:** the external display reaches the NVIDIA GPU as connector `DP-2`, carried over the **USB-C port (DisplayPort-alt-mode)** — this chassis has no full-size DisplayPort and the HDMI port (`HDMI-A-1`) is unused. The DP-over-USB-C link (through the Type-C controller/retimer) is exactly where NVIDIA's auto-validation tends to come back negative → `vrr_capable=0`.
- The manual override that would force it is **`nvidia-settings`, which is X11-only**; this laptop is **Wayland-only with no X11 session installed**, so there is no supported way to flip it.

So "different hardware" is the whole story — specifically the **display wiring** (native DP vs USB-C DP-alt), not the weaker GPU.

## What did NOT fix it (ruled out, in order tested)

- **Primary GPU.** Tested forcing NVIDIA as Mutter's primary GPU (udev `mutter-device-preferred-primary` tag); journal confirmed `GPU /dev/dri/card1 selected primary given udev rule`, but **no effect on VRR** — the block is in the driver, not the compositor. The switch is still a useful lever for other reasons (compositor/monitor alignment vs. idle battery) — see the **Optional — which GPU GNOME composites on** section below. Currently **off**: reverted to the AMD iGPU on 2026-06-24.
- **GDM greeter on X11** (a common cause per ArchWiki). Ruled out — greeter runs Wayland (`New session … class 'greeter' … type 'wayland'`).
- **Non-atomic KMS.** Ruled out — both GPUs added "using atomic mode setting."
- **Hardware/driver capability.** Ruled out — NVIDIA Wayland VRR needs ≥ Volta + driver ≥ 525; this is Ada + 580.

## Practical substitute — divisor cap at 330 Hz

VRR is low-value at 330 Hz anyway (~3 ms refresh granularity), so a fixed cap that cleanly divides the refresh gives flat frametimes without it: **110** (330/3) or **165** (330/2), set in MangoHud (`fps_limit`). See the Marvel Rivals / MangoHud notes.

## If you ever do want it enabled

The only path is getting NVIDIA to set `vrr_capable=1` (enable "Allow unvalidated G-SYNC Compatible"). Currently that means one of: an X11 session with `nvidia-settings` (none installed), trying a different physical link (HDMI port, or a different USB-C→DP cable / dock that validates), or a future driver that auto-validates this monitor over USB-C. Not worth it for the 330 Hz gain.

## Optional — which GPU GNOME composites on (Mutter primary)

**Current state: AMD iGPU (the default). The NVIDIA-primary udev rule was removed 2026-06-24.**

In Hybrid mode GNOME/Mutter composites on the **boot-VGA GPU**, which here is the **AMD iGPU** (`card2`, `boot_vga=1`). A single udev tag forces it onto the **NVIDIA dGPU** (`card1`, PCI `0000:01:00.0`) instead. This changes only the *render/compositing* GPU — it does **not** touch supergfxctl mode (stays Hybrid, so suspend still works, unlike the MUX path in [`gpu-mux-suspend.md`](gpu-mux-suspend.md)).

| Mutter primary | Pro | Con |
|---|---|---|
| **AMD iGPU** — default, current | dGPU runtime-suspends → better idle battery | compositor not on the GPU driving the external monitor |
| **NVIDIA dGPU** | compositor aligned with the external-monitor GPU (`DP-2`) | dGPU held awake → higher idle power |

Neither setting unlocks VRR (the `vrr_capable=0` block is in the NVIDIA driver — see root cause above).

**→ Switch to NVIDIA primary** (create the rule, reboot):

```sh
printf '%s\n%s\n' \
  '# NVIDIA dGPU (0000:01:00.0) as Mutter primary; stay Hybrid so sleep still works' \
  'SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", TAG+="mutter-device-preferred-primary"' \
  | sudo tee /etc/udev/rules.d/61-mutter-primary-gpu.rules
sudo reboot
```

Confirm: `journalctl -b | grep 'selected primary'` → `card1 selected primary given udev rule`.

**← Switch back to AMD primary** (remove the rule, reboot):

```sh
sudo rm -f /etc/udev/rules.d/61-mutter-primary-gpu.rules
sudo reboot
```

Confirm: that journal line is gone — Mutter falls back to the `boot_vga=1` amdgpu card.

## Related

- [`gpu-mux-suspend.md`](gpu-mux-suspend.md) — why dGPU-only mode (which *would* make NVIDIA the sole GPU and might change validation) is off the table: it breaks s2idle.
- [`amdgpu-gfx-ring-timeout.md`](amdgpu-gfx-ring-timeout.md) — the iGPU crash; unrelated to VRR, same hybrid context.

## Sources

- ArchWiki — Variable refresh rate: <https://wiki.archlinux.org/title/Variable_refresh_rate>
- NVIDIA forum — "monitor not detected as vrr capable" / allow unvalidated G-SYNC Compatible: <https://forums.developer.nvidia.com/t/g-sync-compatible-monitor-not-detected-as-vrr-capable-24g2w1g4/237332>
- NVIDIA forum — G-Sync/FreeSync under Wayland: <https://forums.developer.nvidia.com/t/feature-g-sync-freesync-under-wayland-session/220822>
