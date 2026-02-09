# OpenRGB with i2c_dev Blacklist (9950X3D)

Keep the **i2c_dev blacklist** when you need it for DDC (see [Mouse stutter](../mouse-stutter.md)). Use OpenRGB on demand by loading the module only when needed.

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

**Apply profile at login (no i2c needed):** Run `openrgb -p "PROFILE_NAME"` from session autostart so it gets DISPLAY and exits on its own (no timeout hack). Profile name must match the `.orp` filename (without `.orp`) in `~/.config/OpenRGB/` exactly (e.g. `my profile.orp` → `"my profile"`).

Reference desktop file (in repo: `docs/cachyos/nvidia/openrgb-apply-profile.desktop`):

```ini
[Desktop Entry]
Type=Application
Name=OpenRGB apply profile
Comment=Load and apply OpenRGB profile at login, then exit
Exec=openrgb -p "my profile"
X-GNOME-Autostart-enabled=true
```

Install (no sudo): copy to autostart. GNOME runs it at login; it appears in **Settings → Apps → Startup** so you can turn it off there if needed.

```bash
mkdir -p ~/.config/autostart
cp docs/cachyos/nvidia/openrgb-apply-profile.desktop ~/.config/autostart/
```

If your profile name is not `my profile`, edit `Exec=openrgb -p "your profile name"` in the copied file.

If you previously used the systemd service, disable it: `systemctl --user disable openrgb-profile.service`
