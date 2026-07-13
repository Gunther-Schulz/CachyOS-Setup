# Packages (Install)

**pacman:**
```bash
sudo pacman -S rclone cuda nvtop betterbird gparted steam pavucontrol veracrypt lftp s-tui
sudo pacman -S lutris wine lib32-freetype2 freetype2 lib32-gnutls
```

**AUR (yay):**
```bash
yay -S brave-bin google-chrome miniconda3 gitkraken svn ttf-ms-fonts ttf-mac-fonts adobe-base-14-fonts numix-gtk-theme
yay -S galaxybudsclient-bin logiops heroic-games-launcher-bin visual-studio-code-bin   # MS binary build (marketplace access) — needed for LaTeX Workshop
yay -S wkhtmltopdf-bin claude-code-router   # HTML→PDF; Claude Code model router
yay -S earlyoom-git   # OOM daemon; enable it, systemd-oomd stays disabled (see inventory §5). Tune via /etc/default/earlyoom
yay -S ryzen_smu-dkms-git   # AMD Ryzen SMU sensor driver, exposes pm_table at /sys/kernel/ryzen_smu_drv (see hardware/motherboard-fans.md)
yay -S ddc-mode-switcher usb-link-speed-tray-git rclone-bisync-manager-git   # own tools (AUR): XG27JCG mode toggle, USB link-speed tray, rclone bisync
yay -S asusctl rog-control-center asusctltray-git   # laptop only
```
