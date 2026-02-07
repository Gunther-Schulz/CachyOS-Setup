# Joplin

`yay -S joplin joplin-desktop?`

**Taskbar icon (Wayland):** Copy desktop file and set StartupWMClass:
```bash
cp /usr/share/applications/joplin.desktop ~/.local/share/applications/
echo "StartupWMClass=@joplin/app-desktop" >> ~/.local/share/applications/joplin.desktop
update-desktop-database ~/.local/share/applications
```
Set database path (e.g. hidrive) in Joplin.
