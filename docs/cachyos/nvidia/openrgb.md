# OpenRGB with i2c_dev Blacklist (9950X3D)

Keep the **i2c_dev blacklist** for DDC (keyboard repeat / possible stutter). Use OpenRGB on demand by loading the module only when needed.

**On demand (recommended):**
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

**Apply profile on boot (no i2c needed):** Because the GPU (and some devices) don't save to device, OpenRGB must **stay running** to hold the profile. Run it at login **minimized to tray** (no full GUI) so it loads the profile and keeps it applied.

**Do not create a new desktop file.** Copy the system one and modify that copy (icon, StartupWMClass, etc. stay correct).

**Autostart (run at login):**

```bash
mkdir -p ~/.config/autostart && cp /usr/share/applications/org.openrgb.OpenRGB.desktop ~/.config/autostart/openrgb-profile.desktop
```

Then edit `~/.config/autostart/openrgb-profile.desktop`: set `Name=OpenRGB (profile)`, `Comment=...`, `Exec=openrgb --startminimized --profile "PROFILE_NAME"` (use the exact profile name as in `~/.config/OpenRGB/*.orp`, e.g. `"my profile"` for `my profile.orp`), and add `X-GNOME-Autostart-enabled=true`.

**Applications menu (launch from app list):**

```bash
cp /usr/share/applications/org.openrgb.OpenRGB.desktop ~/.local/share/applications/openrgb-profile.desktop
```

Edit `~/.local/share/applications/openrgb-profile.desktop` the same way (Name, Comment, Exec; omit `X-GNOME-Autostart-enabled` if you don’t want autostart). Then:

```bash
update-desktop-database ~/.local/share/applications
```

**Changes to make in the copied file:** `Name=OpenRGB (profile)`, `Comment=...`, `Exec=openrgb --startminimized --profile "PROFILE_NAME"` — the profile name must match the `.orp` filename (without `.orp`) in `~/.config/OpenRGB/` exactly (e.g. file `my profile.orp` → `--profile "my profile"`). For autostart only, add `X-GNOME-Autostart-enabled=true`. Leave Icon, StartupWMClass, TryExec, etc. as in the system file.

GNOME reads `~/.config/autostart/` automatically — once the file is there, it runs at next login and shows in **Settings → Apps → Startup**. To disable, remove the file or turn it off there. Quit OpenRGB from the tray when you want it to stop.
