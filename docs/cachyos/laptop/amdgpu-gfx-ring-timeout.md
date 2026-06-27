# Laptop: amdgpu iGPU GPU reset → GNOME/Wayland session dies (Brave-triggered)

**Machine:** Laptop (FA607PV) — Radeon iGPU (Raphael, Ryzen 9 7845HX), hybrid with NVIDIA RTX 4060.

**Status:** ✅ **Cause identified 2026-06-25 — Brave's GPU process.** Mitigation **escalated 2026-06-28**: disabling only Brave's HW *video* decode (`VaapiVideoDecoder`) was **insufficient** — it faulted again with VA-API confirmed off on the live process, while just sitting in claude.ai chat with **no video playing** — so the fix is now to disable Brave's GPU process entirely (`--disable-gpu`). The earlier *linux-firmware regression* theory is **falsified on this machine** (see [Ruled out](#ruled-out--linux-firmware-regression-real-upstream-not-this-machines-cause)): it crashed again while running the "good" downgraded firmware, with a page fault that names `Process brave`.

## Symptom

Whole GNOME session drops to GDM (looks like the machine "crashed"), but the system stays up — **no reboot**, uptime keeps counting. On Wayland a GPU reset tears down every GL context at once, so `gnome-shell`, `Xwayland`, Brave, Discord, Enpass all abort together and GDM restarts the session ~12 s later.

**Precursor (the tell):** for a short while beforehand the whole display — *including the mouse cursor* — freezes for ~1–2 s every ~30 s while background work keeps running (audio, downloads, etc. continue). Those are the gfx ring **soft-recovering** (`ring … reset succeeded` / `device wedged, but no recovery needed`); the session only dies when one reset finally **fails** into a full MODE2 reset. A boot can log many soft-recoveries before a fatal one.

In practice it fires **while using Brave** — first noticed during video, but it also fires with **no video at all** (e.g. just sitting in claude.ai chat). Started the moment the AMD iGPU began compositing the desktop (hybrid mode); **never happened when the NVIDIA dGPU drove everything** — which is the basis for the last-resort fix below.

## Root cause — Brave (Chromium) GPU process faults the iGPU shader engine

A **Chromium GPU-process bug on gfx11 AMD APUs**, not our config. Brave submits a command stream that makes a shader reference a GPU buffer with the wrong permission/lifetime (first pinned on the decoded-video frame, but it also fires with no video — so it's Brave's **general GPU raster/compositing**, not just decode). The iGPU takes a **gfxhub UTCL2 permission page fault**; when the gfx ring can't soft-reset, amdgpu escalates to a **full GPU MODE2 reset** — destroying all GL/Wayland contexts.

Kernel fingerprint (journal) — the page fault **names Brave**; gnome-shell is just the next victim holding the ring:

```
amdgpu …: [gfxhub] page fault (src_id:0 ring:24 vmid:5 pasid:…)
amdgpu …:  Process brave … thread brave:cs0
amdgpu …:   … from client 0x1b (UTCL2)
amdgpu …:   Faulty UTCL2 client ID: SQC (data) (0xa)     ← shader data access
amdgpu …:   PERMISSION_FAULTS: 0x3   (MAPPING_ERROR/WALKER_ERROR = 0 → page IS mapped, accessed wrongly)
amdgpu …: ring gfx_0.1.0 timeout … Process gnome-shell
amdgpu …: Ring gfx_0.1.0 reset failed
amdgpu …: GPU reset begin! … MODE2 reset → GPU reset succeeded → device wedged
```

Mesa side, from `coredumpctl info` on `gnome-shell` — the lost GPU context makes Mesa `abort()` mid buffer-swap, taking the shell (and every GL client) down:

```
abort (libc) → libgallium → dri_flush → libEGL_mesa
→ cogl_onscreen_swap_buffers_with_damage (libmutter-cogl) → … (SIGABRT)
```

It is a **permission** fault (page mapped, accessed with wrong rights) ⇒ a software bug in *what Brave submits*. There is nothing for the kernel to retry, which is why `amdgpu.noretry` cannot help (that only rescues *not-present* faults).

**Known, widespread bug class — not unique to this machine:**
- Brave #48448 — "Brave GPU process triggers amdgpu hard reset on Linux" — same cascade. <https://github.com/brave/brave-browser/issues/48448>
- cosmic-comp #2149 — identical "gfxhub page fault (UTCL2 permission fault) → GPU reset → full session restart" on a Radeon iGPU. <https://github.com/pop-os/cosmic-comp/issues/2149>
- microsoft/vscode #238088, and the Framework 16 Phoenix (gfx1103) MES-hang reports — same gfx11-APU page-fault-to-reset from a Chromium/Electron GPU process.

## Fix — take Brave's GPU process off the iGPU (`--disable-gpu`)

Every fault block names `Process brave … thread brave:cs0`, so Brave's GPU process is the **originator** (gnome-shell is just the next victim holding the ring). The reliable fix is to stop Brave submitting **any** GPU work to the iGPU: disable its GPU process. The browser then rasterizes/composites on the CPU — trivial on the 7845HX — so the iGPU never sees the faulting shader submission. The UI stays responsive; the only cost is software WebGL/canvas and a little more CPU/battery while browsing.

`~/.config/brave-flags.conf` (the Arch `brave-bin` wrapper at `/usr/bin/brave` reads this; `#` and blank lines are ignored, one flag per line):

```
--disable-gpu
```

Fully restart Brave (`pkill -x brave`, then reopen), then verify:

```sh
# brave://gpu → "Graphics Feature Status" reads "Software only" / "Disabled" across the board
journalctl -k -g 'page fault|ring .*timeout|device wedged' --since "1 hour ago"   # empty = fixed
```

### Why not the lighter `--disable-features=VaapiVideoDecoder`

That was the first attempt: the theory was that only the *decoded-video* buffer faulted, so forcing CPU video decode would dodge it while keeping GPU raster/WebGL. **It proved insufficient** — on 2026-06-28 the laptop faulted again with VA-API confirmed off on the live process (`Process brave`, `SQC (data)`, `PERMISSION_FAULTS: 0x3`, gfx ring timeout), crashing while just sitting in **claude.ai chat with no video playing**. So the faulting path is Brave's general raster/compositing, not video decode — which is why the whole GPU process has to come off the iGPU. (If an upstream Brave/Mesa fix later lands, step back down to `VaapiVideoDecoder` and retest.)

**Laptop-only — deliberately NOT shared via dotfiles.** The desktop hides its AMD APU ([hardware/hide-amd-apu.md](../hardware/hide-amd-apu.md)), so Brave there runs entirely on the RTX 5090 and is unaffected; pushing this flag to the desktop would needlessly force software rendering. This doc holds the canonical copy of the flag; recreate `~/.config/brave-flags.conf` from it on a fresh laptop install.

This makes the older `LIBVA_DRIVER_NAME=radeonsi` pin ([environment-hybrid.md](environment-hybrid.md)) **moot** for the crash: that kept HW decode on the iGPU to dodge a *cross-GPU* decode crash; with Brave's GPU process disabled there is no GPU decode at all. The env var is harmless — leave it.

### Last resort — hand GNOME compositing back to the NVIDIA dGPU

If `--disable-gpu` somehow doesn't hold (Brave faulting with **no** GPU process would be very surprising), or if killing browser GPU accel proves too costly day-to-day, the decisive fix is to stop the **iGPU from compositing the desktop** at all — the bug never occurred when the NVIDIA dGPU drove everything. Do it with the **Mutter-primary udev rule**, which keeps the system in **Hybrid mode so s2idle suspend still works**: see [gnome-vrr-external-monitor-hybrid.md → which GPU GNOME composites on (Mutter primary)](gnome-vrr-external-monitor-hybrid.md#optional--which-gpu-gnome-composites-on-mutter-primary). Tradeoff: higher idle battery draw (the dGPU can't fully power down while it composites). **Do not** use the MUX → dGPU-only switch for this — that one *breaks* s2idle suspend ([gpu-mux-suspend.md](gpu-mux-suspend.md)).

## Ruled out — linux-firmware regression (real upstream, NOT this machine's cause)

The first investigation blamed an AMD **SMU/GC firmware regression** shipped in `linux-firmware` ≥ 20251125 (a real, widely-reported bug) and downgraded `linux-firmware-amdgpu` to `20251111-1`, pinned via `IgnorePkg`. On 2026-06-25 the session **crashed again on that downgraded firmware**, with the Brave page fault above — a signature the firmware hangs *don't* have (those show a clean ring timeout, `MAPPING_ERROR: 0x0`, **no** page fault). So the firmware regression is **not** what crashes this laptop. (The doc had always flagged it "unconfirmed on this machine"; this confirms it negative.)

**Undo the downgrade** — the pin blocks firmware updates for no benefit. As of **2026-06-28** the machine is **still pinned** at `linux-firmware-amdgpu 20251111-1` (repos have `1:20260622-1`), and the firmware is now *doubly* proven innocent — it crashed again on this old blob on 2026-06-28 with the Brave page fault, no video. Because a Brave fault (`Process brave` page fault) and a firmware regression (page-fault-free ring timeout) have **distinguishable signatures**, you can unpin **now** without muddying the diagnosis — no need to wait. Edit + update + reboot:

```sh
# headless one-liner to drop the pin (keeps a .bak):
sudo sed -i.bak -E '/^IgnorePkg[[:space:]]*=[[:space:]]*linux-firmware-amdgpu[[:space:]]*$/d' /etc/pacman.conf
# or interactively: sudoedit /etc/pacman.conf  → delete the line  IgnorePkg = linux-firmware-amdgpu
sudo pacman -Syu                   # pulls the current linux-firmware-amdgpu (1:20260622-1+)
sudo reboot                        # firmware only loads at GPU init
pacman -Q linux-firmware-amdgpu    # confirm it advanced past 20251111-1
```

By mid-2026 the current blob almost certainly carries the upstream revert of the Nov-2025 regression. **Safety net:** if a *page-fault-free* ring timeout (a ring timeout with **no** `Process brave` line) ever appears after updating, that would be the firmware — re-add the `IgnorePkg` line and downgrade again.

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
- ❌ **Mesa / kernel version swaps** — crashed on both 7.0.12 and 7.1.1 (same firmware, same Brave path).

## Secondary cleanup

`supergfxd` is inactive and the hybrid setup is hand-wired. Independent of this bug — revisit only if you want ASUS's switcher to manage a clean Hybrid mode.
