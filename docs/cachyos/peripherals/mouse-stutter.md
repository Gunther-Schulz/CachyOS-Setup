# Mouse Stutter and Keyboard Sticking/Repeating

One or more of these can help alleviate mouse stuttering and keyboard sticking/repeating keys.

**Status:** After applying the measures below, stutter has not returned for several days. In retrospect the mouse was always somewhat sluggish; it only became obvious when it got really bad. After the fix, overshooting UI elements for a few days was normal until re-adapting to a responsive mouse. Gaming did not seem to be affected even when the desktop felt sluggish.

---

## 1. Install patched mutter

**Mutter render-source patch (LP #2081140):** See `content/mutter-49-render-source/README.md` in this repo (build, install, revert).

**GNOME / AUR:** gnome-shell-performance or mutter-performance from AUR have been tested. 13.x stutter reported again, 12.x smooth. Mouse stutters reported with Heaven/Unigine + Telegram panel at high GPU load; Brave at 100% didn't reproduce. On Cosmic, mouse issues in doc reportedly gone.

---

## 2. Re-pair mouse (and keyboard) with dongle using Solaar

Re-pair the devices with the receiver/dongle using [Solaar](https://pwr.github.io/Solaar/) so the link is clean.

---

## 3. Use only a single receiver for both devices

Use one receiver/dongle for both mouse and keyboard instead of separate receivers to reduce interference and bus load.

---

## 4. Block DDC (NVIDIA Wayland)

**Symptoms:** Mouse and display stutter together; keyboard freeze then repeat keys.

**Cause:** i2c/DDC traffic over NVIDIA DisplayPort can cause bus contention. Blocking DDC may not fix stutter but often fixes the keyboard repeat issue.

**Fix:** Blacklist `i2c_dev` so I2C (including DDC) isn't exposed to userspace. Monitor detection/resolution still work.

```bash
echo 'blacklist i2c_dev' | sudo tee /etc/modprobe.d/blacklist-i2c-dev.conf
sudo mkinitcpio -P
sudo reboot
```

**Verify:** `lsmod | grep i2c_dev` shows nothing.

**If you use OpenRGB:** Keep the blacklist and load `i2c_dev` on demand when running OpenRGB; see [OpenRGB with i2c_dev blacklist](../nvidia/openrgb.md).

---

## 5. Turn off Bluetooth

Turn off Bluetooth to rule out interference (not sure if the OS switch is sufficient; try disabling the service or adapter if needed).

---

## Stutter triggered by GPU load, persists after app exit

**Observed:** No stutter → start wan2gp and generate a video → mouse stutters during generation → stutter **persists** after generation finishes and after exiting wan2gp.

**Different in detail, similar overall (loading model):** While *loading* a model in wan2gp (not during generation), stutter occurred once that behaved differently in detail: constant intensity, did not go away on its own (unlike the usual GPU-load stutter, which varies and clears after a few seconds). It only stopped after power-cycling the mouse (Logitech MX Master 4: switch mouse off and on again). Same family of issue overall.

**Workaround:** Power-cycling the mouse (unplug/replug USB or turn receiver off/on, or switch mouse off/on, e.g. MX Master / MX Master 4) can clear the stutter — suggests the bad state was in the input path (USB/hid or compositor's view of that device).
