# VLC

Config: `~/.config/vlc/vlcrc` (tracked in dotfiles) — the recipes below are one-time edits; the applied result lives in the tracked file.

**Resume playback:** 0=Never, 1=Ask, 2=Always. Or via Tools → Preferences → Interface → "Continue playback".
```bash
sed -i 's/^#\?qt-continue=.*/qt-continue=2/' ~/.config/vlc/vlcrc && grep '^qt-continue=' ~/.config/vlc/vlcrc
```
Expected output: `qt-continue=2`

**Disable systray:** Tools → Preferences → Interface → uncheck "Show systray icon".

## NVIDIA + Wayland artifacts

Two fixes for different compositors — pick the one matching your session, don't stack both:

**GNOME/Wayland:** keep HW accel, use XVideo output instead of OpenGL (avoids the artifacts):
```bash
cp ~/.config/vlc/vlcrc ~/.config/vlc/vlcrc.backup
sed -i 's/^#\?avcodec-hw=.*/avcodec-hw=any/' ~/.config/vlc/vlcrc
sed -i 's/^#\?vout=.*/vout=xcb_xv/' ~/.config/vlc/vlcrc
sed -i 's/^#\?avcodec-dr=.*/avcodec-dr=1/' ~/.config/vlc/vlcrc
```

**Cosmic/Wayland:** disable HW accel entirely, use OpenGL output:
```bash
cp ~/.config/vlc/vlcrc ~/.config/vlc/vlcrc.backup
sed -i 's/^#avcodec-hw=any/avcodec-hw=none/' ~/.config/vlc/vlcrc
sed -i 's/^#vout=$/vout=gl/' ~/.config/vlc/vlcrc
```

Restart VLC after either change. Verify decode path: `vdpauinfo`, `vainfo`. If artifacts persist: try `avcodec-hw=vdpau`, `GDK_BACKEND=x11 vlc`, or `avcodec-dr=0`.
