# RAM surge damage via connected devices

**Machine:** Desktop

## What happened

Two Corsair RAM modules died in sequence from external surge through data
connections (evidence/claim paperwork: `~/Downloads/amazon_claim/`): first while
connecting a Poco F5 via USB (cause never determined, not reproducible), second
when a self-powered amplifier suffered heat death and pushed voltage out through
its signal connection. Electrical environment verified OK — wall outlet and all
power strips tested with an outlet tester; amp and PC shared the same wall
outlet. Ground loop / house wiring ruled out — don't re-investigate.

## Standing rule

No devices with their own power supply on the desktop's USB/audio ports.

**Poco F5 — unverified candidate for incident 1:** its reverse/OTG charging can
push power *out* over USB-C. The desktop's rear USB-C is a power **source** (USB
10Gbps Type-C, PD 3.0 30W — ASUS spec sheet, not machine-verified), so a
reverse-charging phone meeting a PD-source port is a VBUS-contention scenario —
plausible but not proven; "cause never determined" above still stands. Mitigation
regardless: disable reverse charging on the phone, never plug it into the rear
USB-C. A phone reads as a harmless data device but can source power.

General rule for anything cable-linked (applies to the laptop + Orico dock too):
all devices connected by a data cable (USB, Thunderbolt, HDMI, audio) draw power
from the same outlet or strip — same ground point means no equalizing current
through the data cable's shield. Same wall outlet ≡ same strip; different
breaker circuits is where risk starts. Note this would **not** have prevented
either incident above (both were device-internal failures) — it closes the
remaining path, not the past one.

## Diagnostic signal

The board absorbed two surges. If RAM shows memtest errors or instability,
suspect the **mainboard** (memory controller / power delivery) before the RAM.
Verification steps + status: [todo.md](../todo.md).

Board booted fine with a known-good RAM pair → memory controller + tested slots
survived; gross board damage largely ruled out, small latent-degradation tail
only. The **rear USB-C port itself is untested** — never tried since the
incident. A dead port would be a *demonstrable* defect (strengthens any RMA); a
working one leaves no proven board fault. Test once the PC is up, with a
**disposable** USB-C device (cheap flash drive) — never the phone, nothing
self-powered: does it enumerate? Data working is all that needs knowing; don't
stress PD/charging.

## Warranty / insurance

Purchase decision 2026-07-23: replacement RAM from Marketplace seller
PCSPEZIALIST-BONN (AE Computer GmbH, German brick-and-mortar) at €800 instead of
€900 Amazon-direct; Assurant Geräteschutz tier €800–849.99. Per the AVB,
external causes are classified as "unbeabsichtigte Beschädigung" → surge damage
is plausibly covered from day 1 (own reading, not a binding confirmation).
Documents: `~/Downloads/amazon_claim/assurant-geraeteschutz-*.pdf`.
