# Todo

- **Desktop:** board RMA option — seller agreed weeks back; unsure if still honored. Confirm the window is still open (free, one message) **before** deciding. Decide with two facts in hand: (a) USB-C port test result, (b) memtest on new RAM — dead port or memtest errors → take RMA; both clean → keep + monitor, RMA only if evidence appears. Background: [hardware/ram-surge-damage.md](hardware/ram-surge-damage.md).
- **Desktop:** RAM/board surge check — background: [hardware/ram-surge-damage.md](hardware/ram-surge-damage.md).
  1. Memtest86+ overnight (≥4 full passes) with the known-good RAM (`sudo pacman -S memtest86+-efi`, then pick it in the boot menu). Short test already ran clean; long run outstanding.
  2. Repeat right after the new RAM is installed — within the 14-day withdrawal window, so a DOA module is trivial to return.
  3. Until several clean weeks have passed, check weekly:
     ```sh
     journalctl -k --since "-7 days" | grep -iE "mce|edac|machine check|corrected error"
     ```
  Both memtests clean + several quiet weeks → board cleared, remove this item and mark the doc closed. Any memtest error → suspect the board, not the RAM.
  4. Wider board checkout (surge went through data lines twice — test beyond the memory path), all quick:
     - every USB port enumerates with a **disposable** stick (rear USB-C is the untested suspect — see the doc; data-only, nothing self-powered);
     - PCIe links at full width/speed: `sudo lspci -vv | grep -E "LnkCap|LnkSta"` — degraded lanes (e.g. x16 card at x8, or Gen5 at Gen3) are a classic silent surge symptom;
     - NVMe health: `sudo smartctl -a /dev/nvme0` — media errors + error-log entries zero;
     - audio codec + LAN: play something over each output once, `ethtool <if>` link at expected speed;
     - start `rasdaemon` (`sudo pacman -S rasdaemon && sudo systemctl enable --now rasdaemon`) — persistent MCE/EDAC ledger (`ras-mc-ctl --errors`), stronger than the weekly journal grep because it survives reboots and catches corrected errors that never hit the journal.
- **Desktop:** 9950X3D efficiency tuning — 105 W ECO mode + Curve Optimizer undervolt (~−15…−25 per core, weakest cores less). **Sequencing: only AFTER the surge-check item above is fully cleared** — CO instability and latent board damage look identical (random reboots, corrected MCEs); tuning before the board is cleared destroys the diagnostic signal.
  CO stability testing on Linux (CoreCycler/OCCT are Windows-first; equivalents):
  1. Single-core cycling (the failure mode CO creates — solo boost at low current): `mprime` (AUR `mprime-bin`) pinned to one core at a time via `taskset -c N`, SSE torture first (highest boost = most fragile), then AVX2; cycle all 32 threads, ~10 min/core overnight, script the loop. This *is* CoreCycler minus the PowerShell.
  2. `y-cruncher` (native Linux tarball) component stress tests — different math paths, catches what mprime misses.
  3. Idle soak a full day — CO fails at *idle/light load*, not just under stress. Watch `ras-mc-ctl --errors` / `journalctl -k | grep -iE "mce|machine check"`: corrected Cache Hierarchy errors = back off 5 on that core even without a crash (the Linux equivalent of WHEA 18/19 warnings).
  4. Any single failing core: relax only that core's offset (+5), re-run; then a week of normal use as final judge.
  Payoff at 105 W: ~95% multicore, ~half the load power/heat; gaming and single-thread unaffected (X3D loads run 60–90 W anyway).
- Use Limine bootloader on the laptop (automatic snapshots supported).
- Compare Brave Wayland flags to standard values; possibly remove some.
- **Desktop:** confirm the PowerMizer max-perf autostart is removed and PowerMizer is back to default (`nvidia-settings -q [gpu:0]/GpuPowerMizerMode`).
- **Desktop:** enlarge the `/boot` partition so more Limine snapshots fit — see [recovery/boot-part-enlarge.md](recovery/boot-part-enlarge.md).
- **Desktop:** check the active OOM daemon (`systemctl is-active earlyoom systemd-oomd`) — it should match the laptop (earlyoom on, systemd-oomd off, per `system-setup-inventory.md` §5). If it doesn't match, figure out whether there's a reason before "fixing" it.
- **Desktop:** verify + remove the now-unneeded GNOME screencast workaround — the VA-API blocklist autostart (`~/.config/autostart/gnome-screencast-vaapi-blocklist.desktop`) **and** the `GST_PLUGIN_FEATURE_RANK` line in `/etc/environment` (recording works fine without them on the laptop; test the recorder on the desktop, then delete both).
- **Desktop:** verify the PipeWire sample-rate ladder actually engages on the mobo optical out — see [audio/sample-rates.md](audio/sample-rates.md). Everything there was measured on the **laptop**; the desktop's figures come from the ASUS spec sheet, not the machine. After `systemctl --user restart pipewire`:
  ```sh
  aplay -l                                       # find the ALC1220P digital device
  aplay -D hw:<N>,<M> --dump-hw-params /dev/zero # capability: expect 44100…192000, S24/S32
  pw-metadata -n settings | grep clock.rate      # daemon's live allowed-rates
  cat /proc/asound/card<N>/pcm<M>p/sub0/hw_params # truth, while 44.1 material plays
  ```
  Success = `hw_params` reports `44100` on CD-rate material instead of `48000`.
- Room correction for the desktop hi-fi chain (PC → mobo optical → WiiM Vibelink). Blocked on hardware: needs a **calibrated** measurement mic (miniDSP UMIK-1, ~€100, ships with a per-unit calibration file) — a phone mic or the Razer Seiren is uncalibrated and rolls off in the bass, i.e. exactly where correction is the only thing that reliably works. Toolchain is verified present: `paru -S roomeqwizard` (REW, needs Java — installed), and PipeWire 1.6.8 has `param_eq` (reads REW's APO export via `filename`), `convolver` (FIR/impulse response), and the `bq_*` biquads builtin in `libspa-filter-graph-plugin-builtin.so` — no extra plugins. **Correct only below ~300 Hz:** room modes are minimum-phase, so minimum-phase biquads fix magnitude and phase together; above the Schroeder frequency you'd be EQ'ing reflections into the direct sound. Write it up as `audio/room-correction.md` (next to `noise-suppression.md` — same PipeWire filter-chain category) once it's measured and working.
