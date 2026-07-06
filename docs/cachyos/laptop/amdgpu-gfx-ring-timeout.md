# Laptop: amdgpu iGPU GPU reset → GNOME/Wayland session dies (Electron/Chromium-triggered)

**Machine:** Laptop (FA607PV) — Radeon iGPU (Raphael, Ryzen 9 7845HX), hybrid with NVIDIA RTX 4060.

**Status:** ✅ **Fix applied 2026-06-30 — GNOME compositing moved off the iGPU onto the NVIDIA dGPU** (Mutter-primary udev rule — see [Fix](#fix--take-the-igpu-out-of-the-compositing-path-composite-on-the-nvidia-dgpu)). Structurally verified at boot (compositor + every Electron GPU process on the dGPU, **zero faults**); the desktop **never crashed before the iGPU started compositing** and the crashes tracked that change, so this is almost certainly the cure — **multi-day heavy use is the final proof.** The bug itself is an **Electron/Chromium GPU-process bug on the gfx11 AMD iGPU** — *not* Brave-specific and *not* our config: Brave first exposed it, then the **Claude Desktop** Electron app tripped the **byte-for-byte identical fault** on 2026-06-30 (`Process claude`, `SQC (data)`, `PERMISSION_FAULTS 0x3`) with Brave not even running. Because *any* Electron app can trigger it, the durable fix takes the **iGPU out of the compositing path** instead of disabling each app's GPU process one at a time. The per-app `--disable-gpu` is now a documented stopgap; the *linux-firmware regression* theory is **falsified on this machine** (see [Ruled out](#ruled-out--linux-firmware-regression-real-upstream-not-this-machines-cause)).

## Symptom

Whole GNOME session drops to GDM (looks like the machine "crashed"), but the system stays up — **no reboot**, uptime keeps counting. On Wayland a GPU reset tears down every GL context at once, so `gnome-shell`, `Xwayland`, and every GL client (Brave, Claude Desktop, Discord, Enpass) abort together and GDM restarts the session ~12 s later.

**Precursor (the tell):** for a short while beforehand the whole display — *including the mouse cursor* — freezes for ~1–2 s every ~30 s while background work keeps running (audio, downloads, etc. continue). Those are the gfx ring **soft-recovering** (`ring … reset succeeded` / `device wedged, but no recovery needed`); the session only dies when one reset finally **fails** into a full MODE2 reset. A boot can log many soft-recoveries before a fatal one.

It fires **while using any Electron/Chromium app the iGPU is compositing** — first caught in **Brave** (during video, then with no video at all, e.g. just sitting in claude.ai chat), then in the **Claude Desktop** app. Started the moment the AMD iGPU began compositing the desktop (hybrid mode); **never happened when the NVIDIA dGPU drove everything** — which is the basis for the fix below.

## Root cause — a Chromium/Electron GPU process faults the iGPU shader engine

A **Chromium GPU-process bug on gfx11 AMD APUs**, shared by every Chromium-based app (Brave, and Electron apps like Claude Desktop / Discord / VS Code), not our config. The app's GPU process submits a command stream that makes a shader reference a GPU buffer with the wrong permission/lifetime. The iGPU takes a **gfxhub UTCL2 permission page fault**; when the gfx ring can't soft-reset, amdgpu escalates to a **full GPU MODE2 reset** — destroying all GL/Wayland contexts.

Kernel fingerprint (journal) — the page fault **names the originating app** (`brave`, `claude`, …); gnome-shell is just the next victim holding the ring:

```
amdgpu …: [gfxhub] page fault (src_id:0 ring:24 vmid:5 pasid:…)
amdgpu …:  Process brave … thread brave:cs0        ← or "Process claude … claude:cs0"
amdgpu …:   … from client 0x1b (UTCL2)
amdgpu …:   Faulty UTCL2 client ID: SQC (data) (0xa)     ← shader data access
amdgpu …:   PERMISSION_FAULTS: 0x3   (MAPPING_ERROR/WALKER_ERROR = 0 → page IS mapped, accessed wrongly)
amdgpu …: ring gfx_0.1.0 timeout … Process gnome-shell
amdgpu …: Ring gfx_0.1.0 reset failed
amdgpu …: GPU reset begin! … MODE2 reset → GPU reset succeeded → device wedged
```

**Same fault from two different apps** — the proof it's the app *class*, not Brave:

| Date | `Process` named | Context |
|---|---|---|
| 2026-06-28 | `brave` | claude.ai chat, **no video**, VA-API already off on the live process |
| 2026-06-30 | `claude` (Claude Desktop, Electron 42) | Brave not running at all |

Both fingerprints are identical: `client 0x1b (UTCL2)`, `SQC (data) (0xa)`, `PERMISSION_FAULTS: 0x3`, `MAPPING_ERROR: 0x0`, gfx ring timeout → MODE2 reset.

Mesa side, from `coredumpctl info` on `gnome-shell` — the lost GPU context makes Mesa `abort()` mid buffer-swap, taking the shell (and every GL client) down:

```
abort (libc) → libgallium → dri_flush → libEGL_mesa
→ cogl_onscreen_swap_buffers_with_damage (libmutter-cogl) → … (SIGABRT)
```

It is a **permission** fault (page mapped, accessed with wrong rights) ⇒ a software bug in *what the app submits*. There is nothing for the kernel to retry, which is why `amdgpu.noretry` cannot help (that only rescues *not-present* faults).

**Known, widespread bug class — not unique to this machine:**
- Brave #48448 — "Brave GPU process triggers amdgpu hard reset on Linux" — same cascade. <https://github.com/brave/brave-browser/issues/48448>
- cosmic-comp #2149 — identical "gfxhub page fault (UTCL2 permission fault) → GPU reset → full session restart" on a Radeon iGPU. <https://github.com/pop-os/cosmic-comp/issues/2149>
- microsoft/vscode #238088, and the Framework 16 Phoenix (gfx1103) MES-hang reports — same gfx11-APU page-fault-to-reset from a Chromium/Electron GPU process.

## Fix — take the iGPU out of the compositing path (composite on the NVIDIA dGPU)

Because *any* Electron/Chromium app can trigger this, the durable fix is **not** to disable each app's GPU process (whack-a-mole — there's no shared flags file across Electron apps; Claude Desktop crashed the session even with Brave's flag in place) but to stop the **iGPU compositing the desktop** at all. The bug never occurred when the NVIDIA dGPU drove everything.

Force **Mutter to composite on the NVIDIA dGPU** with the **Mutter-primary udev rule**, which keeps the system in **Hybrid mode so s2idle suspend still works** — unlike the MUX → dGPU-only switch, which *breaks* s2idle ([gpu-mux-suspend.md](gpu-mux-suspend.md)). Once Mutter's primary is the dGPU, **Chromium auto-selects the NVIDIA render node**, so every Electron/Brave app moves off the iGPU at once. Full how-to: [gnome-vrr-external-monitor-hybrid.md → which GPU GNOME composites on (Mutter primary)](gnome-vrr-external-monitor-hybrid.md#optional--which-gpu-gnome-composites-on-mutter-primary).

```sh
printf '%s\n%s\n' \
  '# NVIDIA dGPU (0000:01:00.0) as Mutter primary; stay Hybrid so sleep still works' \
  'SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", TAG+="mutter-device-preferred-primary"' \
  | sudo tee /etc/udev/rules.d/61-mutter-primary-gpu.rules
sudo reboot
```

**Pair it with `LIBVA_DRIVER_NAME=nvidia`** so HW video decode follows the compositor onto the dGPU (same GPU, no cross-GPU handoff) — see [environment-hybrid.md](environment-hybrid.md#why-libva_driver_name-follows-the-compositor). With the iGPU now compositing nothing, leaving decode on it (`radeonsi`) would *re-introduce* a cross-GPU frame copy.

**Verify (2026-06-30 — all confirmed on this machine):**

```sh
journalctl -b | grep 'selected primary'                        # → card1 … selected primary given udev rule  (NVIDIA)
journalctl -k -b -g 'page fault|ring .*timeout|device wedged'  # → empty
# every Electron/Chromium GPU process now on the NVIDIA node (renderD128), none on renderD129 (iGPU):
for p in $(pgrep -f -- '--type=gpu-process'); do ls -l /proc/$p/fd | grep -o 'renderD12[89]'; done | sort -u
```

Confirmed: compositor on `card1` (NVIDIA), Claude Desktop's GPU process moved from `renderD129` (iGPU, where it faulted) to `renderD128` (NVIDIA), zero faults at boot.

**Tradeoff:** the dGPU can't fully runtime-suspend while it composites → higher idle battery. That's the price of killing the whole crash class; accepted here. To undo (back onto the iGPU): `sudo rm /etc/udev/rules.d/61-mutter-primary-gpu.rules && sudo reboot`, and flip `LIBVA_DRIVER_NAME` back to `radeonsi`.

### Stale-Electron apps (Discord) hang on the dGPU

Moving compositing to the dGPU fixes the crash for every app, but it exposes a **cross-GPU dmabuf** rough edge in apps whose Chromium is too old to follow the compositor:

- **Modern Electron** (Claude Desktop, Electron 42) reads the Wayland compositor's advertised "main device" and renders on the dGPU (`renderD128`) — no problem.
- **Older Electron** (Discord, Electron 37) keeps rendering on the **iGPU** (`renderD129`); its buffer is then an iGPU dmabuf the now-NVIDIA compositor can't import, so the window **hangs blank**:

```
wayland_error: failed to import supplied dmabufs: Could not bind the given EGLImage to a CoglTexture2D
'GPU' process exited with 'abnormal-exit'
```

(Its GPU telemetry reports `gpu_1` = AMD `active:true`, NVIDIA `active:false`.)

**`/etc/environment` can't fix this.** Chromium picks its render GPU internally by enumerating DRM nodes; it **ignores** `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `__EGL_VENDOR_LIBRARY_FILENAMES`, and the PRIME-offload vars (those steer *Mesa/GLX* apps, not Chromium's Ozone picker). Tested with the full NVIDIA-forcing set — Discord still rendered on the iGPU and its GPU process abnormal-exited.

**Fix per stale app: disable its GPU acceleration** so it CPU-renders (SHM buffers import fine; no cross-GPU, and no iGPU-crash risk either). For Discord — see [apps/discord.md](../apps/discord.md) — in `~/.config/discord/settings.json` with Discord closed:

```json
"enableHardwareAcceleration": false
```

Re-enable if the app later ships a newer Electron that follows the compositor.

### Per-app stopgap (lower battery, but whack-a-mole) — `--disable-gpu`

Before the systemic fix, the workaround was to disable an *individual* app's GPU process so it rasterizes/composites on the CPU (fine on the 7845HX), keeping the iGPU as the desktop compositor for better idle battery. For Brave, in `~/.config/brave-flags.conf` (the Arch `brave-bin` wrapper at `/usr/bin/brave` reads it; `#`/blank lines ignored, one flag per line):

```
--disable-gpu
```

This **only covers the one app** — Claude Desktop crashed the session even with Brave's flag active, which is exactly why it was abandoned for the dGPU-compositing fix. It's now kept **commented** in `brave-flags.conf` as a fallback for *if* the udev rule is ever reverted (back onto the iGPU). The lighter `--disable-features=VaapiVideoDecoder` (CPU video decode only) proved **insufficient** even for Brave — it faulted with VA-API confirmed off and no video — so it's the general raster/compositing path that faults, not just decode.

**Laptop-only — deliberately NOT shared via dotfiles.** The desktop hides its AMD APU ([hardware/hide-amd-apu.md](../hardware/hide-amd-apu.md)), so Brave there runs entirely on the RTX 5090 and is unaffected. This doc holds the canonical copy of the laptop flags.

## Ruled out — linux-firmware regression (real upstream, NOT this machine's cause)

The first investigation blamed an AMD **SMU/GC firmware regression** shipped in `linux-firmware` ≥ 20251125 (a real, widely-reported bug) and downgraded `linux-firmware-amdgpu` to `20251111-1`, pinned via `IgnorePkg`. On 2026-06-25 the session **crashed again on that downgraded firmware**, with the app page fault above — a signature the firmware hangs *don't* have (those show a clean ring timeout, `MAPPING_ERROR: 0x0`, **no** page fault). So the firmware regression is **not** what crashes this laptop.

**Undo the downgrade — ✅ done 2026-06-30.** The pin was removed (sed dropped the `IgnorePkg = linux-firmware-amdgpu` line, `.bak` kept), `linux-firmware-amdgpu` updated to **`1:20260622-1`**, and the machine rebooted so the new blob is actually loaded. Verified: no active `IgnorePkg` line in `/etc/pacman.conf`, `pacman -Q linux-firmware-amdgpu` → `1:20260622-1`.

```sh
# (already applied; recorded for a fresh install)
sudo sed -i.bak -E '/^IgnorePkg[[:space:]]*=[[:space:]]*linux-firmware-amdgpu[[:space:]]*$/d' /etc/pacman.conf
sudo pacman -Syu                   # pulls the current linux-firmware-amdgpu (1:20260622-1+)
sudo reboot                        # firmware only loads at GPU init
pacman -Q linux-firmware-amdgpu    # confirm it advanced past 20251111-1
```

**Safety net:** if a *page-fault-free* ring timeout (a ring timeout with **no** `Process <app>` page-fault line) ever appears, that would be the firmware — re-add the `IgnorePkg` line and downgrade again. Anything with a `Process <app>` page fault (like every crash so far) is the Chromium/iGPU bug, not firmware.

Forensic note worth keeping: a firmware-package downgrade does nothing until you **reboot** — in-session GPU resets reuse the already-resident firmware. (An early "fixed" call was premature because the downgraded blob had never been loaded.) The `smu fw version` journal line is identical before/after the downgrade, so it is **not** a usable signal.

Upstream sources for the firmware regression (real bug, just not ours):
- <https://gitlab.freedesktop.org/drm/amd/-/issues/4737>
- <https://github.com/NixOS/nixpkgs/issues/466945> (first bad = 20251125)
- <https://discourse.nixos.org/t/crashing-on-amd-igpu-ring-gfx-0-1-0-timeout/73647>

## Other ruled-out mitigations

- ❌ **PSR disable** (`amdgpu.dcdebugmask=0x10`) — crashed again under it (2026-06-22); removed. It had been hand-injected into the generated `grub.cfg`, not `GRUB_CMDLINE_LINUX_DEFAULT`, so a `grub-mkconfig` regen dropped it. Verify gone: `grep dcdebugmask /proc/cmdline` → empty.
- ❌ `amdgpu.noretry` — cannot help a *permission* fault (see Root cause).
- ❌ `amdgpu.ppfeaturemask=…` — other reporters confirm no effect.
- ❌ **RAM / EXPO** — DDR5-5200 is stock JEDEC; the fault is a GPU-VA permission error, not memory.
- ❌ **Mesa / kernel version swaps** — crashed on both 7.0.12 and 7.1.1 (same firmware, same app path).
- ❌ **Per-app `--disable-gpu` as the *primary* fix** — works for one app but not the class; superseded by the dGPU-compositing switch above. (Still valid as a per-app, lower-battery stopgap.)

## Secondary cleanup

`supergfxd` is inactive and the hybrid setup is hand-wired. Independent of this bug — revisit only if you want ASUS's switcher to manage a clean Hybrid mode.
