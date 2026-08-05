# OpenRGB — profile while awake, dark while asleep

**Machine:** Desktop

Goal and behaviour: `my profile` active whenever the machine is awake; every LED dark
during sleep. Three pieces, each carrying one mechanism:

| piece | what it does | mechanism it handles |
|---|---|---|
| dotfiles `desktop/openrgb-apply-profile.desktop` | applies `my profile` at login | controllers hold whatever they were last told — someone has to tell them |
| dotfiles `desktop/openrgb-sleep.sh` → `/usr/lib/systemd/system-sleep/openrgb.sh` | **pre:** DIMMs → black (scoped, see below), **post:** re-apply `my profile` | DIMM RGB keeps standby power in S3 (stays lit unless told black); motherboard/GPU controllers lose power and wake in firmware rainbow |
| dotfiles `desktop/openrgb-sleep-detectors.json` → `~/.config/OpenRGB-sleep/OpenRGB.json` | scopes the pre-hook: every detector off except Corsair DRAM | pre has no business beyond the DIMMs — board and GPU lose power in S3 and go dark on their own |
| the profile itself (`~/.config/OpenRGB/my profile.orp`) | the desired awake state | must contain **all** devices — see the failure mode below |

## ⚠️ The hook belongs in `/usr/lib`, never `/etc` — systemd scans one directory

**`systemd-sleep` reads sleep hooks from `/usr/lib/systemd/system-sleep/` and nowhere
else.** There is no `/etc` search path, and a hook placed there is silently ignored —
no error, no log line, nothing to find. Established 2026-08-06, three ways:

```sh
strings /usr/lib/systemd/systemd-sleep | grep system-sleep   # → exactly one path, /usr/lib/...
```

`man 8 systemd-suspend.service` (systemd 261) likewise names only the `/usr/lib` path;
and the decisive control — the co-resident `/usr/lib` hook `spd5118.sh` demonstrably
ran on the very suspends where the `/etc` hook emitted nothing (`kernel: spd5118
8-0051: DDR5 temperature sensor…` at each resume).

This cost a day. The hook was installed to `/etc/systemd/system-sleep/openrgb.sh` on
2026-08-05 and **never executed once** — every symptom read as an OpenRGB fault was
simply the absence of any hook at all. **Retracted with it**, because their only
evidence was the behaviour of a script that never ran:

- the suspend abort ("Wakeup pending" + spurious PCIe PME) blamed on the unscoped
  pre-hook — that version was also in `/etc`, so it cannot have aborted anything; the
  PME source is unidentified and unrelated to this file;
- "the unscoped pre set nothing because detection hung on the GPU" — it set nothing
  because it never ran;
- "post does not run when the suspend itself fails" — never observed, unfounded;
- "a fixed post-delay lost the USB re-enumeration race" — never observed, unfounded.

**The sign to recognise next time:** a sleep hook that produces *zero* journal output
is not a failing hook, it is an unexecuted one. Grep the journal for the hook's own
messages before debugging anything the hook does — and note that a grep finding
nothing proves nothing until it has matched a run that *did* happen (see the measured
trace below for what a live one looks like).

The detector scope survives the retraction on design grounds: pre has no business
beyond the DIMMs — the board and GPU lose power in S3 and go dark on their own, and
full detection would touch a GPU the `nvidia` hook (alphabetically earlier) has
already prepared for suspend. Verified: scoped `--list-devices` shows exactly the two
sticks, and the scoped black leaves board/GPU lit. After an OpenRGB update, **new
detectors are unlisted and default ON** — re-verify with
`openrgb --config ~/.config/OpenRGB-sleep --list-devices` (must list exactly the two
DIMMs).

The apply is gated on the device **roster count**, not on the apply's exit code,
because `openrgb -p` exits 0 while silently skipping absent devices (mechanism below).
Hook output is deliberately not silenced — it is the only evidence the hook leaves.

The s2idle fallback error in the journal (`amdgpu … BIOS has not been configured for
suspend-to-idle`) is environmental — this machine sleeps `deep`, the fallback can
never work, ignore it.

## What a working cycle looks like (measured 2026-08-06)

Journal from a live `systemctl suspend`, hook running from `/usr/lib`:

| offset | journal line | meaning |
|---|---|---|
| −2 s | `systemd-sleep[…]: Connection attempt failed` | pre ran; DIMMs written black |
| 0 | `kernel: PM: suspend entry (deep)` | |
| +15 s | `kernel: PM: suspend exit` | resume |
| +24 s | `Connection attempt failed` / **`Profile loaded successfully`** | post applied the profile |

So **~9 seconds of firmware rainbow after resume is normal and expected**, not a
failure: post sleeps 5 s before its first roster check (USB re-enumeration), then
`openrgb -l` costs a few seconds more. No `post waiting` line appeared — the full
4-device roster was back on the *first* check, so the fixed 5 s sleep dominates, not
the retry loop. Pre costs ~2 s of added suspend-entry latency.

Read it back with:

```sh
journalctl -b -o short-iso | grep -iE 'openrgb|systemd-sleep|PM: suspend'
```

Both artifacts are **owned and deployed by the dotfiles repo** (`dot apply`); this doc
carries the why, not a copy.

Verify: sleep the machine — everything dark, RAM included. Wake it — rainbow for ~9 s
while post waits out USB re-enumeration, then profile colors. Confirmed end-to-end
2026-08-06. The hook's two halves can also be exercised without suspending:

```fish
sudo /usr/lib/systemd/system-sleep/openrgb.sh pre suspend    # RAM goes dark at once
sudo /usr/lib/systemd/system-sleep/openrgb.sh post suspend   # ~5 s, then profile back
```

## Reading the saved colors back

The GUI can't show them (below), so this repo carries a reader:

```fish
./tools/openrgb-profile-colors.py            # prints device → hex from the .orp
```

Verified at build time against colors set by hand minutes earlier, and it refuses
("unparseable") rather than ever printing wrong colors when the format drifts —
re-verify against a known color after any OpenRGB format-version bump. Caveat: the
white-only GPU is driven by a brightness field the tool does not parse, so its color
row is meaningless. First run immediately caught a real mismatch: the two sticks had
been saved as `0623FF` and `001EFF` — visually indistinguishable blues (since unified).

## Adjusting a color without the GUI (proven workflow)

One invocation: load the profile (restores every device's saved state, brightness
included), override just the target device, save back:

```fish
openrgb -p "my profile" -d 1 -m direct -c 0623FF -sp "my profile"
./tools/openrgb-profile-colors.py    # verify the write took
```

Two traps, both hit while proving this: `-sp` **appends `.orp` itself** — pass the
bare name, or the save lands in `<name>.orp.orp` and the real profile silently keeps
its old content (the reader then "refutes" a save that simply went elsewhere — check
*which file* you are reading before concluding). And the byte-diff of a correct save
is confined to the changed device's color channels — anything larger means the load
half didn't restore the other devices' state.

## ⚠️ The silent failure mode: a profile apply that skips devices

`openrgb -p` matches profile entries to detected devices on stored identity data
(name **and** location strings — hidraw paths, i2c bus numbers). When enumeration
drifts (BIOS update, kernel change), the entry stops matching and the apply **skips
that device while still printing "Profile loaded successfully"**.

⚠️ The 2026-08-05 incident once cited here as an instance ("RAM blue, everything else
off/rainbow") is **no longer good evidence** — that is character-for-character what
the missing sleep hook produced, so the two cannot be told apart after the fact. The
matching mechanism is real and the roster gate rests on it; treat the incident as
unattributed. A genuine instance shows `openrgb -l` returning fewer than the 4
expected devices, or one at a location string the `.orp` does not contain.

The sign: a partial apply with a success message. The fix: open the GUI, set all
devices, re-save the profile under the same name. The sleep hook's dark half is immune
by design — `openrgb -m direct -c 000000` broadcasts to whatever is detected, no
profile matching involved.

## The profile, human-readable (rebuild reference if the .orp is lost)

Saved 2026-08-05, all devices in **Direct** mode, brightness up:

| device | color |
|---|---|
| Corsair Vengeance RGB DDR5 (both sticks) | `0623FF` (blue) |
| ASUS ROG STRIX B850-G | `FF2600` (orange-red) |
| RTX 5090 FE | white (hardware is white-only; the setting is brightness) |

⚠️ When re-saving in the GUI: these controllers are **write-only** — the GUI cannot
read colors back, so it shows its own staged state (black, brightness at minimum)
even while the hardware is lit. Set color **and raise the Brightness slider** on every
device before saving, or the profile stores "correct color at brightness zero".

The same applies to editing: **"Load Profile" pushes colors to the devices but does
not populate the picker fields.** That one is an OpenRGB UI shortcoming, not a hardware
limit — the values are in the file it just parsed; the picker simply never syncs from
loaded state (the per-LED preview strip on the device page may still show them).
Possibly a 1.0rc3 regression — operator recollection of 0.9 behaving better,
unverified; re-check after the next OpenRGB update. To adjust from the current
setting, read the saved values with `tools/openrgb-profile-colors.py`, type the hex
into the picker and nudge from there; if a new value sticks, update the table in the
same edit.

## Device notes

- Each Corsair DIMM is its **own OpenRGB device** (direct SMBus, not routed through
  the board's Aura controller) — a profile must include both sticks.
- The RTX 5090 FE illumination is **white-only**: OpenRGB drives brightness; any color
  renders white. Not a bug.
- "Connection attempt failed" on every CLI invocation is OpenRGB failing to find an
  SDK server before falling back to direct control — harmless noise.
