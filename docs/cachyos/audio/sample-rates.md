# PipeWire sample rates — don't resample everything to 48 kHz

**Machine:** Both

Stock PipeWire ships `default.clock.allowed-rates = [ 48000 ]` (see the commented
defaults in `/usr/share/pipewire/pipewire.conf`). One allowed rate means the graph
can never switch, so **every 44.1 kHz source — most music — is sample-rate
converted to 48 kHz in software**, regardless of what the hardware could do
natively.

The fix is the drop-in `pipewire/99-clock-rates.conf`, **tracked in dotfiles**
(deployed by `dot apply`). It widens the list to the full ladder:

```
default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]
```

## Why one shared file is correct for both machines

`allowed-rates` is a **permission list, not a demand** — PipeWire intersects it
with what the ALSA device actually advertises. So the same file does the right
thing on hardware with very different ceilings, and there is no reason to
machine-scope it:

| Machine | Digital out | Effect of the wider list |
|---|---|---|
| **Desktop** | B850-G onboard **ALC1220P** optical S/PDIF → Vibelink (no dock in this chain) | Graph follows the source; the 44.1 → 48 resample disappears. ⚠ *Unverified — desktop is down (RAM failure); rates read from the ASUS spec sheet, not the machine.* |

The two chains are separate and fixed — laptop: USB → Orico dock → optical → Vibelink;
desktop: mobo optical → Vibelink. Only the laptop's runs through the dock, so only the
laptop is subject to its 16-bit/48 kHz ceiling.
| **Laptop** | Orico dock, JMTek `0c76:1277` | **Inert.** The chip advertises only 48 kHz, so PipeWire still lands there. See [Orico dock → TOSLINK](../peripherals/orico-dock-toslink.md) — that ceiling is hardware, not config. |

## Verify

Configured value vs. what the daemon is actually running are different questions —
check both. The config only takes effect after a PipeWire restart.

```sh
systemctl --user restart pipewire            # required after changing the drop-in

pw-config list context.properties | grep allowed-rates   # merged config (parses?)
pw-metadata -n settings | grep clock.rate                # what the daemon runs
cat /proc/asound/card<N>/pcm<M>p/sub0/hw_params          # the truth, while audio plays
```

`hw_params` is the one that settles it — it reports the rate and format the
hardware is being fed right now. Find `<N>`/`<M>` with `aplay -l`.

To see what a device is *capable* of, rather than what it's doing:

```sh
aplay -D hw:<N>,<M> --dump-hw-params /dev/zero
```

## Undo

```sh
mv ~/.config/pipewire/pipewire.conf.d/99-clock-rates.conf{,.disabled}
systemctl --user restart pipewire
```

## Don't buy a DDC to fix this

An external USB→S/PDIF converter ("re-clocker") does **nothing** for the desktop —
the ALC1220P already does native 44.1 at 24-bit over its own clock, and optical is
galvanically isolated, so neither jitter nor noise is on the table. On the laptop a
DDC *would* lift the dock's hard 16-bit/48 kHz ceiling, but that is a resolution
fix, not a clock fix. Jitter audibility thresholds sit ~3 orders of magnitude above
what any of this hardware produces.
