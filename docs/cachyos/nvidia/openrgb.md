# OpenRGB (9950X3D)

**Machine:** Desktop.

## ⚠️ If the lights are dark, check the BIOS before debugging OpenRGB

**`Advanced → Onboard Devices Configuration → LED lighting → When system is in
working state`.** If this is **`Aura Off`**, the board's RGB is disabled in
hardware and **OpenRGB will accept every write, report success, and change
nothing** — colours, per-zone writes, and hardware effect modes all "work" with
zero visible result. There is no error to find, because nothing is failing.

**Root cause of the 2026-08 outage** (resolved 2026-08-04 by setting `All On`).
The tell that distinguishes this from an OpenRGB fault: **RAM and GPU still
respond, board LEDs and RGB-header fans do not.** RAM and GPU carry their own
controllers and are not behind the board's Aura gate; the mobo logo and the fan
headers are.

The four options are two independent switches, which is the part that reads as
confusing — "Aura" here means *decorative RGB*, as opposed to *functional*
indicator LEDs (Q-LED, power/standby):

| Setting | Decorative RGB | Functional LEDs |
|---|---|---|
| `All On` | on | on |
| `Aura Only` | on | off |
| `Aura Off` | **off** | on |
| `Stealth Mode` | off | off |

`Aura Off` is the trap: the machine looks alive and normal, so nothing suggests
lighting was disabled on purpose.

There is a **second** toggle beneath it for *sleep, hibernate and soft-off
states* — separate switch, same options. Also relevant: `Advanced → APM
Configuration → ErP Ready`, which cuts standby power to the RGB rails when
enabled.

i2c_dev is no longer blacklisted (needed for XG27JCG DDC). OpenRGB can use I2C when the module is loaded. If you re-blacklist for [mouse stutter](../peripherals/mouse-stutter.md), load on demand:

**On demand (if i2c_dev blacklisted):**
```bash
sudo modprobe i2c-dev
# run OpenRGB, set colors
sudo modprobe -r i2c_dev
```

**Load at every boot (optional):** Remove blacklist, then:
```bash
echo 'i2c-dev' | sudo tee /etc/modules-load.d/i2c-dev.conf
sudo mkinitcpio -P
sudo reboot
```
Keyboard repeat issue may return.

**Check chipset I2C (if OpenRGB doesn’t see hardware):** `lsmod | grep i2c_piix4`

---

**RTX 5090 FE (and other NVIDIA Illumination GPUs):** OpenRGB does not implement save-to-device for the NVIDIA Illumination (NvAPI) controller. “Saving Not Supported” for the GPU is expected; use “Save Profile” / “Load Profile” to re-apply colors when you start OpenRGB.

---

**Apply profile at login (no i2c needed):** Run `openrgb -p "PROFILE_NAME"` from session autostart so it gets DISPLAY and exits on its own (no timeout hack). Profile name must match the `.orp` filename (without `.orp`) in `~/.config/OpenRGB/` exactly (e.g. `my profile.orp` → `"my profile"`).

> **Open question — does `-p` alone actually apply?** During the outage above,
> `openrgb -p "my profile"` printed nothing and exited 0, while
> `openrgb --server -p "my profile"` printed *"Profile loaded successfully"*.
> That difference is real at the **output** level, but it was never confirmed at
> the **lighting** level, because the BIOS gate meant *no* invocation could have
> produced a visible change. **Re-test now that lighting works:** run plain
> `openrgb -p "my profile"` from a terminal with the lights in a different
> state. Colours change → the autostart above is correct as written; nothing
> changes → add `--server` to the `Exec=` line in dotfiles.

The desktop entry is managed by dotfiles — `~/dev/Gunther-Schulz/dotfiles/desktop/openrgb-apply-profile.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=OpenRGB apply profile
Comment=Load and apply OpenRGB profile at login, then exit
Exec=openrgb -p "my profile"
X-GNOME-Autostart-enabled=true
```

**Deploy:** managed by dotfiles (`dotfiles/desktop/`, desktop-scoped) — run `~/dev/Gunther-Schulz/dotfiles/dot apply`. GNOME runs it at login; it appears in **Settings → Apps → Startup** so you can turn it off there if needed.

If your profile name is not `my profile`, edit `Exec=openrgb -p "your profile name"` in `dotfiles/desktop/openrgb-apply-profile.desktop`.

If you previously used the systemd service, disable it: `systemctl --user disable openrgb-profile.service`
