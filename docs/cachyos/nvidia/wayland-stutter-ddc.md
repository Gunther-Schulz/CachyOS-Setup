# NVIDIA Wayland: Mouse/Display Stutter — DDC Block (Preliminary)

**Symptoms:** Mouse and display stutter together; keyboard freeze then repeat keys.

**Cause:** i2c/DDC traffic over NVIDIA DisplayPort can cause bus contention. Blocking DDC may not fix stutter but often fixes the keyboard repeat issue.

**Fix:** Blacklist `i2c_dev` so I2C (including DDC) isn’t exposed to userspace. Monitor detection/resolution still work.

```bash
echo 'blacklist i2c_dev' | sudo tee /etc/modprobe.d/blacklist-i2c-dev.conf
sudo mkinitcpio -P
sudo reboot
```

**Verify:** `lsmod | grep i2c_dev` shows nothing.

**Also try:** Mutter render-source patch (LP #2081140) — see `mutter-49-render-source/README.md` at repo root if present.
