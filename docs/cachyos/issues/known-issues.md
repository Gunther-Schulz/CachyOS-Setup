# Known Issues

**Grey screen in GDM, stuck cursor, Ctrl+Alt+F1 not working:** Often dual-monitor. Disconnect second monitor and login dialog appears.

**Double key press in GRUB menu:** Seen on 4K Acer; disconnecting it forces display to Dell 2K where input is slow but works. Try: lower `GRUB_GFXMODE` (e.g. 1280x1024x32) in `/etc/default/grub`, `sudo update-grub`; disable CSM in BIOS.
