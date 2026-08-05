# OpenRGB — profile while awake, dark while asleep

**Machine:** Desktop

Goal and behaviour: `my profile` active whenever the machine is awake; every LED dark
during sleep. Three pieces, each carrying one mechanism:

| piece | what it does | mechanism it handles |
|---|---|---|
| dotfiles `desktop/openrgb-apply-profile.desktop` | applies `my profile` at login | controllers hold whatever they were last told — someone has to tell them |
| dotfiles `desktop/openrgb-sleep.sh` → `/etc/systemd/system-sleep/openrgb.sh` | **pre:** DIMMs → black (scoped, see below), **post:** re-apply `my profile` | DIMM RGB keeps standby power in S3 (stays lit unless told black); motherboard/GPU controllers lose power and wake in firmware rainbow |
| dotfiles `desktop/openrgb-sleep-detectors.json` → `~/.config/OpenRGB-sleep/OpenRGB.json` | scopes the pre-hook: every detector off except Corsair DRAM | pre must touch **only** what stays powered in S3 — see the suspend abort below |
| the profile itself (`~/.config/OpenRGB/my profile.orp`) | the desired awake state | must contain **all** devices — see the failure mode below |

## ⚠️ Why the pre-hook is scoped to the DIMMs — a suspend abort

The first, unscoped pre-hook ran full device detection (GPU i2c, USB Aura hidraw)
seconds before suspend entry — and the first suspend after its install **aborted**
("Wakeup pending. Abort CPU freeze" + a spurious PCIe PME). A later suspend
**succeeded with the same unscoped hook installed**, so the abort attribution is
**probabilistic at most** — same hook, one abort, one success. The scope is right
regardless: pre never had business beyond the DIMMs — the board and GPU **lose power
in S3 and go dark on their own**; only the RAM keeps standby power — and full
detection touches a GPU the `nvidia` sleep-hook (alphabetically earlier) has already
prepared for suspend. That touch is also the likely reason the unscoped pre set
**nothing** (RAM stayed lit through the successful suspend): a hang there, killed by
the 30 s timeout, exits before any color is written. The scoped detector config makes
pre touch only the SMBus DIMMs (verified: scoped `--list-devices` shows exactly the
two sticks, including under a display-less stripped environment; the scoped black
leaves board/GPU lit).

Post lessons from the same night: **post does not run when the suspend itself fails**
(a failed attempt can still reset the board to rainbow — re-apply by hand), a fixed
post-delay **lost the USB re-enumeration race** once (board stayed rainbow after a
successful suspend), and `openrgb -p` **exits 0 while silently skipping absent
devices** — so the hook gates the apply on the full device roster (count), not on the
apply's exit code. Hook output goes to the journal deliberately: the first field
failure was invisible only because every line ended in `>/dev/null 2>&1`.

The s2idle fallback error in the journal (`amdgpu … BIOS has not been configured for
suspend-to-idle`) is environmental — this machine sleeps `deep`, the fallback can
never work, ignore it. After an OpenRGB update, **new detectors are unlisted and
default ON** — re-verify the scope:
`openrgb --config ~/.config/OpenRGB-sleep --list-devices` must list exactly the two
DIMMs.

Both artifacts are **owned and deployed by the dotfiles repo** (`dot apply`); this doc
carries the why, not a copy.

Verify: sleep the machine — everything dark, RAM included. Wake it — profile colors,
no rainbow.

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
that device while still printing "Profile loaded successfully"**. Observed 2026-08-05:
the RAM (stable `/dev/i2c-8` address) applied; the ASUS board and GPU were silently
skipped, leaving "RAM blue, everything else off/rainbow".

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
