# Mouse Stutter and Keyboard Sticking/Repeating

**Machine:** Desktop.

**Most likely cause:** RF link quality between the mouse/keyboard and the receiver. After re-pairing (below) the stutter stopped and hasn't returned. (In retrospect the mouse was always a bit sluggish — it only became obvious once it got bad.)

## Fix — escalate in order

1. **Power-cycle the mouse** (switch off/on, e.g. MX Master 4) — first line; clears a bad input-path state (USB/HID or the compositor's view of the device).
2. **Unplug / replug the receiver** — next, if the mouse on/off didn't help.
3. **Re-pair with [Solaar](https://pwr.github.io/Solaar/)**, using a **single receiver** for both mouse and keyboard — the actual fix for the RF-link cause (clean link + less inter-receiver interference/bus load).

**Heavy GPU load can trigger it** (e.g. generating a video in wan2gp), and it can *persist after the app exits* — step 1 (on/off) usually clears it.

## Fallback candidate — i2c_dev / DDC (unconfirmed, not the cause)

`i2c_dev` stays loaded (XG27JCG DDC needs it). i2c/DDC traffic over NVIDIA DisplayPort is a *possible* contributor — mostly to the **keyboard** repeat issue, not the mouse stutter. If stutter persists after the steps above, try blacklisting it:
```bash
echo 'blacklist i2c_dev' | sudo tee /etc/modprobe.d/blacklist-i2c.conf
sudo mkinitcpio -P && sudo reboot        # undo: rm the file, mkinitcpio -P, reboot
```
(If you use [OpenRGB](../nvidia/openrgb.md), it needs `i2c_dev` too.)
