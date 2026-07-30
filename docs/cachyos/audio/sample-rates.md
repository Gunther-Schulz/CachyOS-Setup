# PipeWire sample rates — don't resample everything to 48 kHz

**Machine:** Both

Stock PipeWire ships `default.clock.allowed-rates = [ 48000 ]` (see the commented
defaults in `/usr/share/pipewire/pipewire.conf`). One allowed rate means the graph
can never switch, so **every 44.1 kHz source — most music — is sample-rate
converted to 48 kHz in software**, regardless of what the hardware could do
natively.

Two drop-ins, both **tracked in dotfiles** (deployed by `dot apply`):

| File | Does |
|---|---|
| `pipewire/99-clock-rates.conf` | widens `allowed-rates` to `[ 44100 48000 88200 96000 176400 192000 ]` so the graph follows the source |
| `pipewire/99-resample-quality.conf` | raises `resample.quality` from stock 4 to 10 for the conversions that remain |

Rate-following removes the *unconditional* conversion, not every conversion: a sink
runs at one rate, so two streams of different rates sharing it still force one.
That is what quality 10 improves — and why it matters more on the laptop, where the
dock makes every 44.1 track a conversion anyway.

## Why one shared file is correct for both machines

`allowed-rates` is a **permission list, not a demand** — PipeWire intersects it
with what the ALSA device actually advertises. The same file therefore does the
right thing on hardware with very different ceilings, and there is no reason to
machine-scope it.

| Machine | Digital out | Effect of the wider list |
|---|---|---|
| **Desktop** | B850-G onboard **ALC1220P** optical S/PDIF | Graph follows the source; the 44.1 → 48 resample disappears. Verified on the machine 2026-07-30. |
| **Laptop** | Orico dock, JMTek `0c76:1277` | **Inert.** The chip advertises only 48 kHz, so PipeWire still lands there. See [Orico dock → TOSLINK](../peripherals/orico-dock-toslink.md) — that ceiling is hardware, not config. |

Both chains end at the same Vibelink amp; only the laptop's runs through the dock,
so only the laptop is subject to its 16-bit/48 kHz ceiling.

Desktop capability, read from the codec rather than a spec sheet:

```
/proc/asound/card2/codec#0, Node 0x06 [Audio Output]
  rates [0x5f0]: 32000 44100 48000 88200 96000 192000
  bits  [0xe]:   16 20 24
```

**176400 is not offered** — that entry in the list is inert here, which is harmless
(permission list). The bits line also means `alsa.resolution_bits = 16`, which
PipeWire reports on the node, is a probe-time artifact and not a 16-bit ceiling.

## Verify

Configured and running are different questions, and the gap between them is the
trap: **a drop-in deployed after the daemon started does nothing until PipeWire is
restarted**, while the file on disk looks correct the whole time. Check the live
value, never the file.

```sh
systemctl --user restart pipewire pipewire-pulse   # required after changing a drop-in

pw-metadata -n settings | grep -E 'clock.rate|allowed-rates'   # what the daemon runs
pw-config -n pipewire-pulse.conf list stream.properties        # merged config (parses?)
pw-dump | grep resample.quality                                # 10 on live stream nodes
cat /proc/asound/card<N>/pcm<M>p/sub0/hw_params                # the truth, while audio plays
```

`hw_params` settles it — the rate and format the hardware is being fed right now.
Find `<N>`/`<M>` with `aplay -l`. A source playing at 44100 into a sink reporting
48000 (visible together in `pw-top`) is the resample, live.

`resample.quality` must reach the **client**, so it lives in `client.conf.d` *and*
`pipewire-pulse.conf.d`. A drop-in in `pipewire.conf.d` alone has no effect on app
playback — that is the whole reason dotfiles links one file into two places.

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

## Don't chase bit-perfect / exclusive-mode players

Measured on the desktop 2026-07-30, not argued: a 16/44.1 FLAC played through the
**Pulse API** (the path VLC and browsers use) into a null sink, monitor captured and
compared sample by sample, came back **bit-identical over 1,215,488 samples** at
100 % volume. The negative control — same test at volume 0.5 — correctly showed a
0.1250 gain ratio (−18.06 dB, GNOME's cubic curve), so the test can detect a defect.

With rate-following on and volume at 100 %, PipeWire alters nothing. An ALSA
`hw:`-direct player has nothing to win, and it costs all other audio on the machine.

## Don't lock the sink volume

`channelmix.min-volume = 1.0` does pin a sink at unity, and the pinned output is
bit-identical. **It also defeats mute** (mute is volume→0 at the same channel-mix
stage; measured peak 26805 instead of silence). With a 200 W/ch amp on 45 W
speakers that is a safety regression for zero gain, since unity is already
bit-perfect. If accidental attenuation is the worry, unbind the volume keys in
GNOME and keep mute.

## Don't pin the graph rate with `clock.force-rate`

`pw-metadata -n settings 0 clock.force-rate <n>` **restarts pipewire-pulse** (the
service start timestamp moves and every Pulse client drops). For a test rig, create
a null sink at the wanted rate and assert the rate instead of forcing it.
