# Laptop: amdgpu iGPU gfx ring timeout → GNOME/Wayland session dies

**Machine:** Laptop (FA607PV) — Radeon iGPU (Raphael, Ryzen 9 7845HX), hybrid with NVIDIA RTX 4060.

**Status:** 🧪 **Fix staged, validating since 2026-06-23.** Strongly-suspected cause: `linux-firmware` SMU/GC regression (≥ 20251125) — well-sourced upstream, but **not yet empirically confirmed on this machine**. Fix under test: `linux-firmware-amdgpu` downgraded to `20251111-1`, now running on the **same kernel that crashed (7.1.1)** with the PSR-disable hack removed — a clean-isolated test, no kernel confound. The earlier PSR-disable mitigation **failed** (crashed under it) and is ruled out.

## Symptom

Whole GNOME session drops to GDM (looks like the machine "crashed"), but the system stays up — **no reboot**, uptime keeps counting. On Wayland a `gnome-shell` crash tears down the entire session, which is why it feels total. GDM restarts the shell ~12s later. Started **the moment the AMD iGPU was enabled** (hybrid mode); never happened while the iGPU was dormant and the NVIDIA dGPU drove everything.

## Validation status — IMPORTANT gotcha (2026-06-23)

The first draft's "✅ CONFIRMED" was **premature**: the downgraded firmware had never actually been loaded while the session kept crashing.

- Downgrade applied to disk: **Mon 2026-06-22 14:04** (`pacman -U …20251111-1`).
- No reboot followed until **2026-06-23**; the machine had booted Mon 11:29 on the *old* `20260519` blob.
- **A firmware-package downgrade does nothing until you reboot.** The GPU resets in between (`SMU is resuming…` at 01:47, 10:20, 11:36) reuse the already-resident firmware — they do **not** reload from disk. So every crash through 2026-06-23 11:36 was still on the old, broken blob. That is why it "crashed again" after the downgrade — not a failure of the fix, but the fix never ran.
- First boot on the downgraded firmware: **2026-06-23**. The validation clock starts here, not at the package downgrade.

**How to confirm the fix is actually active** (the obvious signal is misleading):

- ❌ The journal's `smu fw version = 0x00546900 (84.105.0)` line is **identical** before and after the downgrade — the SMU sub-blob version didn't bump between releases (the regression is likely in a different file in the package, e.g. GC/gfx microcode, which fits the *gfx* ring timing out). Do **not** read this line as "fix is loaded."
- ✅ Reliable signals: `pacman -Q linux-firmware-amdgpu` = `20251111-1`, **and** the continued absence of ring-timeout/wedge events over days.

7.1.1 **accepted** the November firmware (SMU initialized, no "firmware too old" rejection), so the `linux-cachyos-lts` fallback below is not currently needed.

## Root cause — linux-firmware SMU/GC regression (strongly suspected, well-sourced; unconfirmed on this machine)

Not PSR, not Mesa, not RAM, not the kernel. The **AMD SMU firmware shipped since `linux-firmware` 20251125** is broken for Raphael/RDNA APUs. On desktop dGPUs it manifests as "SMU crashes / stuttering"; on an **AMD-iGPU + NVIDIA-dGPU hybrid laptop** it manifests as our exact signature.

Kernel fingerprint (journal):

```
amdgpu 0000:05:00.0: ring gfx_0.1.0 timeout, signaled seq=N, emitted seq=N+2
amdgpu 0000:05:00.0: Ring gfx_0.1.0 reset failed
amdgpu 0000:05:00.0: [drm] *ERROR* Failed to initialize parser -125!
amdgpu 0000:05:00.0: GPU reset begin!
amdgpu 0000:05:00.0: MODE2 reset → GPU reset succeeded → device wedged
```

Mesa side, from `coredumpctl info <pid>` on `gnome-shell`:

```
abort (libc) → libgallium-26.1.2 → dri_flush → libEGL_mesa
→ cogl_onscreen_swap_buffers_with_damage (libmutter-cogl) → … (SIGABRT)
```

The lost GPU context after the reset makes Mesa (`libgallium`) `abort()` mid buffer-swap, taking `gnome-shell` (and any GL client — Brave, etc.) with it. The **NVIDIA dGPU is not involved**.

This iGPU loads `smu_v13_0_0` (`gc_10_3_6` = Raphael). Firmware at crash time: `linux-firmware-amdgpu 1:20260519-1` — carries the regression.

**Sources:**
- Upstream: <https://gitlab.freedesktop.org/drm/amd/-/issues/4737> — AMD SMU firmware regression.
- NixOS issue: <https://github.com/NixOS/nixpkgs/issues/466945> — "linux-firmware: amdgpu regression causing freezes, fix available upstream." First bad = **20251125**.
- NixOS Discourse: <https://discourse.nixos.org/t/crashing-on-amd-igpu-ring-gfx-0-1-0-timeout/73647> — Lenovo 16ARX8 (AMD iGPU + NVIDIA dGPU hybrid), identical `ring gfx_0.1.0` + `parser -125`, crashes within seconds–minutes of enabling hybrid; root cause = linux-firmware regression; fix = older linux-firmware.
- Framework: <https://community.frame.work/t/fyi-linux-firmware-amdgpu-20251125-breaks-rocm-on-ai-max-395-8060s/78554> — corroborates 20251125 as the bad release.

## Fix — downgrade linux-firmware-amdgpu to 20251111-1

Last good = **20251111-1** (immediate predecessor of the bad 20251125). Arch splits AMD firmware into its own package, so only the AMD blob changes — NVIDIA/WiFi/etc. untouched.

```sh
# Option A — downgrade tool (if installed)
sudo downgrade linux-firmware-amdgpu      # pick 20251111-1

# Option B — manual from the Arch Linux Archive
curl -O https://archive.archlinux.org/packages/l/linux-firmware-amdgpu/linux-firmware-amdgpu-20251111-1-any.pkg.tar.zst
sudo pacman -U ./linux-firmware-amdgpu-20251111-1-any.pkg.tar.zst
```

Pin it so `-Syu` doesn't pull the broken version back (the repo's `1:2026…` epoch outranks `20251111`):

```ini
# /etc/pacman.conf
IgnorePkg = linux-firmware-amdgpu
```

Reboot (firmware loads at GPU init), then verify:

```sh
pacman -Q linux-firmware-amdgpu                                   # → 20251111-1
grep -o 'amdgpu.dcdebugmask=[^ ]*' /proc/cmdline                 # (should be removed, see below)
journalctl -k | grep -iE "ring .*timeout|device wedged|parser -125"   # stays empty over days = fixed
```

When a future `linux-firmware-amdgpu` ships the #4737 revert, drop the `IgnorePkg` line and update. If kernel 7.1.x ever rejects the older blob ("firmware too old"), boot `linux-cachyos-lts` (6.18), which pairs cleanly with Nov-2025 firmware.

## Failed / ruled-out mitigations

- ❌ **PSR disable** (`amdgpu.dcdebugmask=0x10`) — applied 2026-06-21, **crashed again under it** 2026-06-22 on kernel 7.1.1. Wrong layer; **removed 2026-06-23**. Note: it had been hand-injected directly into the generated `grub.cfg`, *not* into `GRUB_CMDLINE_LINUX_DEFAULT` (which was already clean) — so a `sudo grub-mkconfig -o /boot/grub/grub.cfg` regen dropped it on the next boot. Verify with `grep dcdebugmask /proc/cmdline` → empty.
- ❌ `amdgpu.ppfeaturemask=…` — other reporters confirm no effect.
- ❌ **RAM / EXPO** — the hang dump showed `WALKER_ERROR: 0x0` / `MAPPING_ERROR: 0x0` (no VM/page fault), and DDR5-5200 is stock JEDEC, not an overclock. Not memory.
- ❌ Mesa / kernel version swaps — same firmware ⇒ same crash (hangs occurred on both 7.0.12 and 7.1.1).

## Secondary cleanup (not the fix, but worth tidying)

`supergfxd` is inactive and the hybrid setup is hand-wired (both GPUs expose an eDP connector; the dGPU sits `active` rather than power-gated). Once the firmware fix is confirmed, optionally let ASUS's switcher manage a clean Hybrid mode:

```sh
sudo systemctl enable --now supergfxd
supergfxctl -g            # check current mode
# supergfxctl -m Hybrid   # if not already
```
