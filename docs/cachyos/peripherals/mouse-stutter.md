# Mouse Stutter and Keyboard Sticking/Repeating

**Machine:** Desktop.

One or more of these can help alleviate mouse stuttering and keyboard sticking/repeating keys.

**Status:** After applying the measures below, stutter has not returned for several days. In retrospect the mouse was always somewhat sluggish; it only became obvious when it got really bad. After the fix, overshooting UI elements for a few days was normal until re-adapting to a responsive mouse. Gaming did not seem to be affected even when the desktop felt sluggish.

**Best guess at the actual fix:** §2/§3 — re-pairing with Solaar and/or using a **single** receiver for both mouse and keyboard. The mutter patch (§1) is likely unrelated (and is upstream now). Several things changed at once, so unconfirmed.

---

## 1. Patched mutter (likely no longer needed)

The `LP #2081140` render-source fix is **upstream in current mutter** — no patch or build needed anymore. (The old `content/mutter-49-render-source/` build guide isn't in this repo.) Probably wasn't the real fix here anyway — see Status above.

**GNOME / AUR (historical):** gnome-shell-performance / mutter-performance from AUR were tried — 13.x stutter returned, 12.x smooth; stutter seen with Heaven/Unigine + Telegram at high GPU load.

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

**Current:** We no longer blacklist `i2c_dev` (needed for XG27JCG DDC/Frame Rate Boost). **Observe if mouse stutter returns.** If it does, re-apply the blacklist below.

**To re-blacklist (if stutter returns):**
```bash
echo 'blacklist i2c_dev' | sudo tee /etc/modprobe.d/blacklist-i2c.conf
sudo mkinitcpio -P
sudo reboot
```

**To un-blacklist:**
```bash
sudo rm /etc/modprobe.d/blacklist-i2c.conf
sudo mkinitcpio -P
sudo reboot
```

**Verify blacklist active:** `lsmod | grep i2c_dev` shows nothing. **Verify un-blacklisted:** `i2c_dev` loads when ddcutil or OpenRGB needs it (or at boot).

**Find blacklist file (if path differs):** `grep -r i2c /etc/modprobe.d/`

**If you use OpenRGB:** See [OpenRGB](../nvidia/openrgb.md).

---

## 5. Turn off Bluetooth

Turn off Bluetooth to rule out interference (not sure if the OS switch is sufficient; try disabling the service or adapter if needed).

---

## Stutter triggered by GPU load, persists after app exit

**Observed:** No stutter → start wan2gp and generate a video → mouse stutters during generation → stutter **persists** after generation finishes and after exiting wan2gp.

**Different in detail, similar overall (loading model):** While *loading* a model in wan2gp (not during generation), stutter occurred once that behaved differently in detail: constant intensity, did not go away on its own (unlike the usual GPU-load stutter, which varies and clears after a few seconds). It only stopped after power-cycling the mouse (Logitech MX Master 4: switch mouse off and on again). Same family of issue overall.

**Workaround:** Power-cycling the mouse (unplug/replug USB or turn receiver off/on, or switch mouse off/on, e.g. MX Master / MX Master 4) can clear the stutter — suggests the bad state was in the input path (USB/hid or compositor's view of that device).
