# Todo

- Use Limine bootloader on the laptop (automatic snapshots supported).
- Compare Brave Wayland flags to standard values; possibly remove some.
- **Desktop:** confirm the PowerMizer max-perf autostart is removed and PowerMizer is back to default (`nvidia-settings -q [gpu:0]/GpuPowerMizerMode`).
- **Desktop:** enlarge the `/boot` partition so more Limine snapshots fit — see [recovery/boot-part-enlarge.md](recovery/boot-part-enlarge.md).
- **Desktop:** check the active OOM daemon (`systemctl is-active earlyoom systemd-oomd`) — it should match the laptop (earlyoom on, systemd-oomd off, per `system-setup-inventory.md` §5). If it doesn't match, figure out whether there's a reason before "fixing" it.
- **Desktop:** verify + remove the now-unneeded GNOME screencast workaround — the VA-API blocklist autostart (`~/.config/autostart/gnome-screencast-vaapi-blocklist.desktop`) **and** the `GST_PLUGIN_FEATURE_RANK` line in `/etc/environment` (recording works fine without them on the laptop; test the recorder on the desktop, then delete both).
- **Desktop:** verify the PipeWire sample-rate ladder actually engages — see [audio/sample-rates.md](audio/sample-rates.md). Everything there was measured on the **laptop**; the desktop's figures come from the ASUS spec sheet, not the machine. Two things to settle, in order:
  1. **Which digital path does the desktop actually use?** Motherboard **ALC1220P** optical S/PDIF (native 44.1, 24-bit, own clock) or the portable **Orico dock** (hard 16-bit/48 kHz ceiling, see [peripherals/orico-dock-toslink.md](peripherals/orico-dock-toslink.md))? The room-correction item below assumes the dock. If the desktop runs through the dock, it inherits that ceiling and the ALC1220P is unused — in which case the rate config is inert there too and the fix is to move the cable, not to change config.
  2. **Then confirm the rates**, after `systemctl --user restart pipewire`:
     ```sh
     aplay -l                                      # find the ALC1220P digital device
     aplay -D hw:<N>,<M> --dump-hw-params /dev/zero # capability: expect 44100…192000, S24/S32
     pw-metadata -n settings | grep clock.rate      # daemon's live allowed-rates
     cat /proc/asound/card<N>/pcm<M>p/sub0/hw_params # truth, while 44.1 material plays
     ```
     Success = `hw_params` reports `44100` on CD-rate material instead of `48000`.
- Room correction for the hi-fi chain (PC → dock → optical → WiiM Vibelink, see [peripherals/orico-dock-toslink.md](peripherals/orico-dock-toslink.md)). Blocked on hardware: needs a **calibrated** measurement mic (miniDSP UMIK-1, ~€100, ships with a per-unit calibration file) — a phone mic or the Razer Seiren is uncalibrated and rolls off in the bass, i.e. exactly where correction is the only thing that reliably works. Toolchain is verified present: `paru -S roomeqwizard` (REW, needs Java — installed), and PipeWire 1.6.8 has `param_eq` (reads REW's APO export via `filename`), `convolver` (FIR/impulse response), and the `bq_*` biquads builtin in `libspa-filter-graph-plugin-builtin.so` — no extra plugins. **Correct only below ~300 Hz:** room modes are minimum-phase, so minimum-phase biquads fix magnitude and phase together; above the Schroeder frequency you'd be EQ'ing reflections into the direct sound. Write it up as `audio/room-correction.md` (next to `noise-suppression.md` — same PipeWire filter-chain category) once it's measured and working.
