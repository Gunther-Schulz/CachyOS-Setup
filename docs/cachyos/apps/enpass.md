# Enpass

`yay -S enpass-bin`

**Desktop file (xcb for Wayland):**
```bash
cp /usr/share/applications/enpass.desktop ~/.local/share/applications/enpass.desktop
sed -i 's|Exec=/opt/enpass/Enpass %U|Exec=env QT_QPA_PLATFORM=xcb /opt/enpass/Enpass %U|g' ~/.local/share/applications/enpass.desktop
update-desktop-database ~/.local/share/applications
```
Google Drive auth needs a Chrome-based browser.
