# Apple Music with Sidra

**Machine:** Both

Alternative Apple Music client — wraps `music.apple.com` in CastLabs Electron
rather than reimplementing the UI. Free, FOSS ([wimpysworld/sidra](https://github.com/wimpysworld/sidra)),
.deb / Snap / AppImage. Kept alongside [Cider](cider.md).

Why it's here: no `AudioContext`, so no DSP and no in-app resample — audio goes
untouched through Chromium's media stack to PipeWire. That sidesteps Cider's
Audio Lab problem structurally instead of by remembering to switch it off. Also
bi-directional MPRIS over D-Bus (`org.mpris.MediaPlayer2.sidra`), which Cider
never got right, and Apple's own UI so it can't drift behind theirs.

## No lossless on Linux — don't expect it

The README's "Lossless audio on macOS and Windows via CastLabs EVS production
VMP signing" **excludes Linux**, which gets only "Widevine DRM via CastLabs
Electron" — no VMP production signing, which is the gate Apple opens lossless
behind. Linux is 256 kbps AAC on both clients, permanently.

Widevine working ≠ lossless working: Widevine is what makes Apple Music play at
all outside an Apple browser; lossless is a second, higher robustness gate.
Several AI assistants conflate the two and claim Linux lossless works. It does
not. Sidra also has no quality readout to check with — asked for and closed
`wontfix` ([#121](https://github.com/wimpysworld/sidra/issues/121)).

Routes that *do* give Apple lossless, none of them good here:

| Route | Blocker |
|---|---|
| Windows / macOS native app | not Linux |
| Apple Music **Android** app (real lossless, 24/48+) | needs Waydroid — broke the host badly once (hung the file browser and other apps; it shares the host kernel: binder modules + LXC + network bridge) — or a phone on a wire |
| Sonos (only platform Apple licensed) | lossless requires their *mobile* app, not the web controller |
| BluOS / HEOS / WiiM | no Apple Music API at all; AirPlay = 256k AAC, i.e. no gain |
| BlissOS in QEMU/KVM | untried; safe (no host kernel modules, unlike Waydroid), but Widevine L3 only — whether Apple serves lossless to L3 is **unverified** |

Switching service (Qobuz — FLAC from the web player, no DRM layer) is the only
option where lossless + Linux + desktop UX all hold at once.
