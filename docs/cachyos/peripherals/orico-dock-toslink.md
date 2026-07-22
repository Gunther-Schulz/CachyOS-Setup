# Orico USB-C Dock → TOSLINK optical (WiiM Vibelink Amp)

**Machine:** Both — the dock is portable; the fix is applied once **per machine** (WirePlumber state is per-user).

Chain: **Orico USB-C dock** → USB audio chip **`0c76:1277` (JMTek "USB PnP Audio Device")** → TOSLINK optical → **WiiM Vibelink Amp**.

## Optical is silent on the analog profile

The chip defaults to profile `output:analog-stereo`, which drives the dock's analog jack — the **TOSLINK optical output carries no signal** there. Optical S/PDIF only outputs on the **`output:iec958-stereo`** profile. That profile switch was the actual fix; setting it as default sends all audio out the optical port.

```sh
CARD=alsa_card.usb-0c76_USB_PnP_Audio_Device-00
pactl set-card-profile "$CARD" output:iec958-stereo
pactl set-default-sink alsa_output.usb-0c76_USB_PnP_Audio_Device-00.iec958-stereo
```

**Persistent, no config file to track:** WirePlumber stores both choices in `~/.local/state/wireplumber/` (`default-profile`, and `default-nodes` → `default.configured.audio.sink=…iec958-stereo`) and restores them on reboot/replug.

## Hard ceiling: 16-bit / 48 kHz only — no 44.1

The chip is a **full-speed (USB 1.1) UAC1** device and advertises exactly one
playback format. From `/proc/asound/card<N>/stream0` on the laptop:

```
Format: S16_LE      Rates: 48000      Bits: 16
Endpoint: 0x01 (1 OUT) (ADAPTIVE)
```

Consequences, none of them fixable in software:

- **44.1 kHz is not offered**, so all CD-rate material is resampled to 48 kHz
  before it leaves the machine. See [PipeWire sample rates](../audio/sample-rates.md).
- **16-bit only** — anything deeper is truncated at the source.
- **`ADAPTIVE`, not `ASYNC`** — the chip slaves its clock to USB frame timing
  instead of running its own. This is the one genuinely jitter-prone USB mode.

Only different hardware (an async UAC2 DDC) lifts this. Widening the PipeWire
rate list does not — it stays inert here.

## Amp side

- Set the Vibelink's input selector to **Optical** (else silent no matter how the PC is routed).
- Optical In is **PCM only** (no Dolby/DTS bitstream). The `iec958-stereo` sink is PCM → fine. Don't pick an `iec958-ac3-surround` profile.

## Verify

```sh
pactl info | grep 'Default Sink'                                    # -> …usb-0c76…iec958-stereo
pactl list cards | awk '/alsa_card.usb-0c76/,/Active Profile/' \
  | grep 'Active Profile'                                           # -> output:iec958-stereo
```

Physical check: look into the TOSLINK connector — a live optical output glows **red**.

## Undo

```sh
pactl set-card-profile alsa_card.usb-0c76_USB_PnP_Audio_Device-00 output:analog-stereo
```
