# VLC

**Resume playback:** 0=Never, 1=Ask, 2=Always. Or via Tools → Preferences → Interface → "Continue playback".
```bash
sed -i 's/^#\?qt-continue=.*/qt-continue=2/' ~/.config/vlc/vlcrc && grep '^qt-continue=' ~/.config/vlc/vlcrc
```
Expected output: `qt-continue=2`

**Disable systray:** Tools → Preferences → Interface → uncheck "Show systray icon".

**Artifacts on Cosmic/Wayland + NVIDIA:** Disable HW accel, use OpenGL output:
```bash
cp ~/.config/vlc/vlcrc ~/.config/vlc/vlcrc.backup
sed -i 's/^#avcodec-hw=any/avcodec-hw=none/' ~/.config/vlc/vlcrc
sed -i 's/^#vout=$/vout=gl/' ~/.config/vlc/vlcrc
```

**Enable HW acceleration (Wayland + NVIDIA):** Use XVideo instead of OpenGL to avoid artifacts. Verify: `vdpauinfo`, `vainfo`.
```bash
cp ~/.config/vlc/vlcrc ~/.config/vlc/vlcrc.backup
sed -i 's/^#\?avcodec-hw=.*/avcodec-hw=any/' ~/.config/vlc/vlcrc
sed -i 's/^#\?vout=.*/vout=xcb_xv/' ~/.config/vlc/vlcrc
sed -i 's/^#\?avcodec-dr=.*/avcodec-dr=1/' ~/.config/vlc/vlcrc
```
Restart VLC. Optimal: `avcodec-hw=any`, `vout=xcb_xv`, `avcodec-dr=1`. If still artifacts: try `avcodec-hw=vdpau`, or `GDK_BACKEND=x11 vlc`, or `avcodec-dr=0`.
