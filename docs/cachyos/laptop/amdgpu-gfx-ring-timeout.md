# Laptop: amdgpu iGPU GPU reset → GNOME/Wayland session dies (Electron/Chromium)

**Machine:** Laptop (FA607PV) — Radeon iGPU (Raphael, 7845HX), hybrid with RTX 4060.

**Status: ✅ fixed 2026-06-30** — GNOME composites on the NVIDIA dGPU (Mutter-primary udev rule); zero recurrence since, under heavy Electron load.

## Symptom

The whole GNOME session drops to GDM (looks like a crash) but the system stays up — no reboot. On Wayland a GPU reset tears down every GL context at once, so gnome-shell + all GL apps (Brave, Claude Desktop, Discord) abort together; GDM restarts ~12 s later. Precursor tell: the display (including the cursor) freezes ~1–2 s every ~30 s (the gfx ring soft-recovering) before one reset finally fails.

Recognize it in the journal — the page fault **names the app**:
```
amdgpu … [gfxhub] page fault … Process brave  (or "Process claude")
  Faulty UTCL2 client ID: SQC (data)   PERMISSION_FAULTS: 0x3
amdgpu … ring gfx_0.1.0 timeout … MODE2 reset → device wedged
```

## Root cause

A **Chromium GPU-process bug on gfx11 AMD iGPUs** (Brave + every Electron app), not our config: the app submits a shader command referencing a GPU buffer with the wrong permission → iGPU permission page-fault → the gfx ring can't soft-reset → full MODE2 GPU reset kills all contexts. It's the app *class*, not Brave — Claude Desktop tripped the byte-identical fault with Brave not running. Being a **permission** fault (page mapped, wrong rights), there's nothing to retry, so `amdgpu.noretry` can't help. Widespread bug ([Brave #48448](https://github.com/brave/brave-browser/issues/48448), cosmic-comp #2149, vscode #238088).

## Fix — take the iGPU out of the compositing path

Any Electron app can trigger it, so the durable fix is to stop the **iGPU compositing the desktop** (the bug never happened when the dGPU drove everything) — not per-app whack-a-mole. Force Mutter to composite on the NVIDIA dGPU; the machine stays **Hybrid, so s2idle suspend still works**:

```sh
printf '%s\n%s\n' \
  '# NVIDIA dGPU (0000:01:00.0) as Mutter primary; stay Hybrid so sleep works' \
  'SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", TAG+="mutter-device-preferred-primary"' \
  | sudo tee /etc/udev/rules.d/61-mutter-primary-gpu.rules
sudo reboot
```

Pair with **`LIBVA_DRIVER_NAME=nvidia`** so HW video decode follows the compositor onto the dGPU — see [environment-hybrid.md](environment-hybrid.md#why-libva_driver_name-follows-the-compositor).

**Tradeoff:** the dGPU can't fully runtime-suspend while compositing → higher idle battery. **Undo:** `sudo rm /etc/udev/rules.d/61-mutter-primary-gpu.rules && sudo reboot`, and flip `LIBVA_DRIVER_NAME` back to `radeonsi`.

**Verify** (the internal panel still *looks* iGPU-driven — that's expected scanout, not a reverted fix; check the live state):
```sh
ls -l /proc/$(pgrep -x gnome-shell)/fd | grep -o 'renderD12[89]' | sort -u   # renderD128 = compositing on the dGPU
journalctl -k -b -g 'page fault|ring .*timeout'                              # empty
```

## Consequence: old-Electron apps (Discord) hang on the dGPU

Modern Electron (Claude Desktop) follows the compositor to the dGPU fine. **Older Electron (Discord)** keeps rendering on the iGPU; its buffer is then an iGPU dmabuf the NVIDIA compositor can't import → the window hangs blank. `/etc/environment` can't fix it (Chromium ignores `GBM_BACKEND`/GLX/PRIME vars for its Ozone GPU pick). Fix per stale app: disable its HW acceleration so it CPU-renders — Discord: `"enableHardwareAcceleration": false` in `~/.config/discord/settings.json` (see [discord.md](../apps/discord.md)).

## Fallback + ruled out

- **Per-app `--disable-gpu`** (e.g. Brave's `~/.config/brave-flags.conf`) is a per-app stopgap only — kept commented as a fallback if the udev rule is ever reverted.
- **Ruled out — a linux-firmware regression:** a downgrade + `IgnorePkg` pin was tried, then falsified (the crash recurred on the downgraded firmware). **Don't re-add the `IgnorePkg = linux-firmware-amdgpu` pin.** Distinguishing sign: a ring timeout *without* a `Process <app>` page-fault line = firmware; *with* one = this app bug.
- Also ruled out (don't re-try): `amdgpu.dcdebugmask=0x10`, `amdgpu.noretry`, `amdgpu.ppfeaturemask`, RAM/EXPO, Mesa/kernel swaps.

**Laptop-only** — deliberately not shared via dotfiles; the desktop hides its AMD APU ([hide-amd-apu.md](../hardware/hide-amd-apu.md)), so Brave there runs on the RTX 5090.
