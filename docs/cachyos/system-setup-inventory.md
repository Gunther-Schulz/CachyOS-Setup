# System-setup inventory

Every concrete **system-level** mutation a fresh machine needs, extracted from
the docs. This is the spec for a future `system-setup.sh` — *not* the script.
As-of **2026-07-12**. Two machines: **laptop** (FA607PV / 7845HX / RTX 4060 /
amdgpu iGPU) and **desktop** (B850-G / 9950X3D / RTX 5090 / NCT6799).

> **⚠️ Read before scripting.**
> - **Source from `docs/cachyos/` only.** Do not derive steps from memory or old
>   notes — some historical fixes were reverted.
> - **Never re-add `IgnorePkg = linux-firmware-amdgpu`** — a historical trap,
>   already reverted (see `laptop/amdgpu-gfx-ring-timeout.md`). The real iGPU
>   ring-timeout fix is the Mutter-primary udev rule, not a firmware downgrade.
> - Bootloader / modprobe / udev tiers have a **boot-breaking blast radius** —
>   build the script incrementally, safe idempotent core first (sysctl, pacman
>   repo+packages, group adds), and verify each tier.
>
> **Path note:** citations to former repo-root files were folded into the tree in
> the 2026-07-12 cleanup: `memory-freeze-mitigation.md` → `system/memory-tuning.md`;
> split-lock from `marvel-rivals-freeze.md` → `gaming/games/marvel-rivals.md`;
> LAMZU rule from `known-issues.md` → `laptop/s3-sleep.md`;
> `boot-part-enlarge.md` → `recovery/boot-part-enlarge.md`;
> remaining open items → `issues/known-issues.md`.

## 1. pacman / repo config (GPG keys, /etc/pacman.conf, package installs)

| Item | Command / content | Source | Machine |
|---|---|---|---|
| Cider GPG key + sign | `curl -s https://repo.cider.sh/ARCH-GPG-KEY \| sudo pacman-key --add -`; `sudo pacman-key --lsign-key A0CD6B993438E22634450CDD2A236C3F42A61682` | `apps/cider.md` | universal |
| Cider repo | `[cidercollective]` / `SigLevel = Required TrustedOnly` / `Server = https://repo.cider.sh/arch` in `/etc/pacman.conf` | `apps/cider.md` | universal |
| Cider install | `sudo pacman -Sy && sudo pacman -S cider` (rm stray `/usr/bin/cider` symlink if migrating) | `apps/cider.md` | universal |
| Core packages | `sudo pacman -S rclone cuda nvtop betterbird gparted steam pavucontrol helvum vercrypt`; `sudo pacman -S lutris wine lib32-freetype2 freetype2 lib32-gnutls` | `apps/packages.md` | universal |
| AUR packages | `yay -S brave-bin miniconda3 gitkraken svn ttf-ms-fonts ttf-mac-fonts adobe-base-14-fonts numix-gtk-theme`; `yay -S galaxybudsclient-bin logiops rclone-manager-git heroic-games-launcher-bin` | `apps/packages.md` | universal |
| ASUS control | `yay -S asusctl rog-control-center` | `apps/packages.md` | laptop |
| Ghostty + Nautilus | `sudo pacman -S ghostty`; `yay -S nautilus-open-any-terminal`; gsettings `terminal 'custom'` + `custom-local-command 'ghostty --working-directory=%s'`; `sudo pacman -Rns gnome-terminal` | `apps/claude-code.md` | universal |
| wl-clipboard | `sudo pacman -S wl-clipboard` | `apps/claude-code.md` | universal |
| Claude Code | `npm install -g @anthropic-ai/claude-code` | `apps/claude-code.md` | universal |
| Claude Desktop | `paru -S claude-desktop-bin claude-cowork-service`; KVM: `paru -S qemu-base qemu-img virtiofsd edk2-ovmf` | `apps/claude-desktop.md` | universal |
| Miniconda + mamba | `yay -S miniconda3`; `sudo /opt/miniconda3/bin/conda install -n base conda-forge::mamba` | `apps/conda-mamba.md` | universal |
| Enpass / Joplin | `yay -S enpass-bin`; `yay -S joplin joplin-desktop` | `apps/enpass.md`, `apps/joplin.md` | universal |
| QGIS | `pacman -S qgis` + `python-gdal python-j2cli python-psycopg2 python-owslib python-lxml mariadb-libs arrow cfitsio podofo libheif poppler` | `apps/qgis.md` | universal |
| TeXLive | `yay -S texlive-full` (remove conflicting `asymptote texlive-*` first; `sudo pacman -S extra/asymptote perl-file-homedir perl-yaml-tiny`) | `apps/texlive.md` | universal |
| VirtualBox | `sudo pacman -S virtualbox virtualbox-host-dkms virtualbox-guest-iso virtualbox-guest-utils`; `sudo gpasswd -a $USER vboxusers`; `sudo modprobe vboxdrv`; `sudo pacman -S arch-install-scripts` | `apps/virtualization.md` | universal |
| PipeWire/Helvum | `sudo pacman -S pipewire-jack helvum` | `audio/pipewire-helvum.md` | universal |
| Jamulus | `yay -S jamulus pavucontrol` | `audio/jamulus.md` | universal |
| DeepFilterNet3 | `paru -S libdeep_filter_ladspa-bin` | `audio/noise-suppression.md` | universal |
| GNOME extras | `yay -S gnome-shell-performance gl-gsync-demo`; `sudo pacman -S gnome-shell-extensions gnome-browser-connector` | `desktop/gnome.md` | universal |
| Lutris / Proton / Steam | `sudo pacman -S lutris proton-cachyos proton-ge-custom steam` (opt: `vulkan-devel`) | `gaming/lutris-ps4.md`, `gaming/proton-steam.md` | universal |
| MangoJuice / ReShade | `yay -S mangojuice`; `yay -S reshade-steam-proton-git` | `gaming/games/marvel-rivals.md`, `gaming/reshade.md` | universal |
| ddc-mode-switcher | AUR `ddc-mode-switcher` | `peripherals/xg27jcg-dual-mode.md` | universal |
| MangoHud | `sudo pacman -S mangohud lib32-mangohud` | `workarounds/mangohud-asus-ec-sensors.md` | desktop |
| NVIDIA open modules | `sudo pacman -S nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia` (removes `*-580xx-*`); rollback with the `nvidia-580xx-*` set | `nvidia/open-kernel-modules.md` | laptop (desktop 5090 is open-only by hw) |

## 2. Files written under /etc

| Path | Content | Source | Machine |
|---|---|---|---|
| `/etc/environment` | Full NVIDIA-primary block (`__GLX_VENDOR_LIBRARY_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `VK_ICD_FILENAMES`, PRIME/Wayland vars, `GST_PLUGIN_FEATURE_RANK`) | `system/environment.md` | **desktop only** — "Do NOT apply wholesale on the laptop" |
| `/etc/environment` | Hybrid PRIME offload vars, `LIBVA_DRIVER_NAME=nvidia` (since 2026-06-30), `__GL_SHADER_DISK_CACHE_SIZE=12000000000`. Back up first: `sudo cp /etc/environment /etc/environment.bak.$(date +%F)` | `laptop/environment-hybrid.md` | **laptop only** |
| `/etc/environment` | `export GSK_RENDERER=cairo` (GNOME GPU-crash workaround) | `desktop/gnome.md` | universal |
| `/etc/udev/rules.d/90-lamzu-no-wakeup.rules` | `ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="373e", ATTR{idProduct}=="001e", ATTR{power/wakeup}="disabled"` + `udevadm control --reload` | `laptop/s3-sleep.md` | laptop |
| `/etc/udev/rules.d/91-bt-controller-no-wakeup.rules` | `ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:06:00.0", ATTR{power/wakeup}="disabled"` | `laptop/s3-sleep.md` | laptop |
| `/etc/udev/rules.d/90-hide-amd-gpu.rules` | `SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x164e", ATTR{remove}="1"` (IDs per board) | `hardware/hide-amd-apu.md` | **desktop only** |
| `/etc/udev/rules.d/61-mutter-primary-gpu.rules` | `SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", TAG+="mutter-device-preferred-primary"` — critical GPU-reset fix, pair with `LIBVA_DRIVER_NAME=nvidia` | `laptop/amdgpu-gfx-ring-timeout.md` | **laptop only** |
| `/etc/udev/rules.d/99-lamzu-maya.rules` | 12-line ruleset for dongle (`373e:001e`) + mouse (`373e:001c`) input/hidraw perms | `peripherals/mouse-lamzu.md` | desktop |
| `/etc/udev/rules.d/99-nvme-usb-performance.rules` | disable USB power for `0bda:9210`, `scheduler=none`, `read_ahead_kb=1024` | `hardware/usb-nvme.md` | universal (ext enclosure) |
| `/etc/modules-load.d/vhost_vsock.conf` | `vhost_vsock` | `apps/claude-desktop.md` | universal (Cowork KVM) |
| `/etc/modules-load.d/nct6775.conf` | `nct6775` | `hardware/motherboard-fans.md` | **desktop only** |
| `/etc/modules-load.d/i2c-dev.conf` | `i2c-dev` | `nvidia/openrgb.md` | desktop (optional) |
| `/etc/modprobe.d/kvm.conf` + `kvm_amd.conf` | `blacklist kvm` / `blacklist kvm_amd` | `apps/virtualization.md` | universal ("some kernels") |
| `/etc/modprobe.d/disable-uas-realtek.conf` | `options usb-storage quirks=0bda:9210:u`; then `sudo mkinitcpio -P` | `hardware/usb-nvme.md` | universal (RTL9210) |
| `/etc/modprobe.d/nvidia.conf` (append) | `options nvidia NVreg_EnableS0ixPowerManagement=1` (+ `NVreg_PreserveVideoMemoryAllocations=1`); `sudo mkinitcpio -P && reboot` | `laptop/gpu-mux-suspend.md` | **laptop only** (no-op on desktop) |
| `/etc/modprobe.d/spd5118-blacklist.conf` | `blacklist spd5118` (DDR5 SPD blocks S3) | `system/sleep.md` | **desktop only** |
| `/etc/modprobe.d/asus-wmi-blacklist.conf` | `blacklist eeepc_wmi` + `blacklist asus_wmi` — ⚠️ laptop NEEDS `asus_wmi` for asusctl | `system/sleep.md` | **desktop only** |
| `/etc/modprobe.d/blacklist-i2c.conf` | `blacklist i2c_dev` (conditional; currently NOT applied — needed for XG27JCG DDC) | `peripherals/mouse-stutter.md` | desktop |
| `/etc/modprobe.d/blacklist-asus-ec-sensors.conf` | `blacklist asus_ec_sensors` (verify before laptop) | `workarounds/mangohud-asus-ec-sensors.md` | desktop |
| `/usr/lib/systemd/system-sleep/spd5118.sh` | `pre) modprobe -r spd5118 ;; post) modprobe spd5118 ;;` + `chmod +x` | `system/sleep.md` | **desktop only** |
| `/etc/sysctl.d/99-split-lock.conf` | `kernel.split_lock_mitigate=0` | `gaming/games/marvel-rivals.md` | universal (gaming) |
| `/etc/sysctl.d/99-memory-freeze-mitigation.conf` | `vm.watermark_scale_factor=100` / `vm.min_free_kbytes=131072` / `vm.swappiness=10` (single home — no separate `99-swappiness.conf`) | `system/memory-tuning.md` | universal |
| `/etc/sysctl.d/` (name TBD) | `vm.max_map_count=262144` | `system/vm-max-map-count.md` | universal |
| `/etc/systemd/system/user@1000.service.d/override.conf` | `ManagedOOMMemoryPressure=kill` / `Limit=20%` / `DurationSec=3` (via `systemctl edit user@1000.service`) | `system/memory-tuning.md` | universal (UID 1000) |
| `/etc/systemd/zram-generator.conf.d/90-zram-size.conf` | `[zram0]` / `zram-size = 24576` / `swap-priority = 100` | `system/memory-tuning.md` | universal |
| `/etc/fstab` | swapfile line `… none swap pri=50 0 0` (ext4, or Btrfs NoCOW `chattr +C`) | `system/memory-tuning.md` | universal |
| `/etc/default/grub` | add `usb-storage.quirks=0bda:9210:u`; `grub-mkconfig -o /boot/grub/grub.cfg` | `hardware/usb-nvme.md` | universal (GRUB) |
| `/etc/default/grub` | `GRUB_DEFAULT=0` + `GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"`; regen | `system/grub-default-kernel.md` | **laptop only** (desktop uses Limine) |
| `/etc/grub.d/40_custom` | Custom safety-mode boot entry (nomodeset, nvidia/nouveau blacklist) | `system/grub-custom.md` | universal (GRUB) |
| `/etc/default/limine` | add `iommu=pt`; `sudo limine-update` | `nvidia/rtx5090-iommu.md` | **desktop only** (5090 + IOMMU freeze) |
| `/etc/default/limine` + `/etc/limine-snapper-sync.conf` | `MAX_SNAPSHOT_ENTRIES=30`; comment out the `=8` line | `system/limine.md` | desktop (Limine) |
| `/etc/asusd/aura_tuf.ron` | via `asusctl aura power-tuf --sleep false` | `laptop/asus-rog.md` | **laptop only** |

## 3. Bootloader / kernel-param quick reference

- `kernel.split_lock_mitigate=0`, `vm.swappiness=10` (+ watermark/min_free), `vm.max_map_count=262144` — sysctl.d, universal
- `usb-storage.quirks=0bda:9210:u` — GRUB or Limine cmdline
- `iommu=pt` (Limine) — **desktop**; `iommu=off amd_iommu=off` is the alternative
- `amdgpu.dcdebugmask=0x10` — **RULED OUT / do not apply** (`laptop/amdgpu-gfx-ring-timeout.md`)
- `/sys/power/mem_sleep=deep` — permanent via a systemd oneshot (`After=suspend.target`) — laptop

## 4. pacman hooks (/etc/pacman.d/hooks/)

| Hook | Trigger | Deploy | Machine |
|---|---|---|---|
| `mr-pso-recompile.hook` | any `nvidia-*utils`/`nvidia-*dkms` + `proton-cachyos*` upgrade → flips `IsGlobalPSOCompiled=True→False` | `sudo cp ~/dev/Gunther-Schulz/dotfiles/gaming/mr-pso-recompile.hook /etc/pacman.d/hooks/` (**hook lives in dotfiles repo**) | universal |

## 5. Services enabled

| Service | Command | Source | Machine |
|---|---|---|---|
| bluetooth | `systemctl enable --now bluetooth` | `peripherals/bluetooth.md` | universal |
| claude-cowork (user) | `systemctl --user enable --now claude-cowork` | `apps/claude-desktop.md` | universal |
| bt-amp-reconnect (user) | full unit at `~/.config/systemd/user/bt-amp-reconnect.service`; `systemctl --user enable` | `peripherals/bluetooth.md` | **laptop only** (SMSL amp, MAC-specific) |
| nvidia-powerd | `sudo systemctl enable --now nvidia-powerd` | `laptop/nvidia-dynamic-boost.md` | **laptop only** (no-op desktop) |
| earlyoom | `sudo systemctl enable --now earlyoom` — active OOM daemon; `systemd-oomd` disabled (kills desktop apps too eagerly under PSI/swap pressure). SIGTERM <10% free RAM+swap, SIGKILL <5%, `--avoid` init/systemd/Xorg/sshd. **Verified laptop; desktop unverified — see todo.md** | `apps/packages.md` | universal |
| mem_sleep oneshot | enable+start (unit body not given verbatim) | `laptop/s3-sleep.md` | laptop |
| coolercontrold | `sudo systemctl restart coolercontrold` (CoolerControl install itself is **undocumented**) | `hardware/motherboard-fans.md` | desktop |

## 6. Autostart .desktop files (~/.config/autostart/)

**`gnome-screencast-vaapi-blocklist.desktop`** (universal; NVIDIA-Wayland screen-record fix; hardcodes UID 1000) — `desktop/gnome.md`:
```
Exec=sh -c 'echo "[\"hwenc-dmabuf-h264-vaapi-lp\",\"hwenc-dmabuf-h264-vaapi\"]" > /run/user/1000/gnome-shell-screencast-pipeline-blocklist'
```

**`nvidia-powermizer-maxperf.desktop`** (**desktop**; ⚠️ flagged possibly-a-no-op in `todo.md` — don't treat as confirmed) — `nvidia/powermizer.md`:
```
Exec=sh -c "nvidia-settings -a [gpu:0]/GpuPowerMizerMode=1"
```

**`openrgb-apply-profile.desktop`** (**desktop**) — now **managed by dotfiles** (`desktop/openrgb-apply-profile.desktop`, machine-scoped symlink); profile name is a placeholder. Supersedes the old `openrgb-profile.service`. — `nvidia/openrgb.md`.

## 7. Other state

| Item | Command | Source | Machine |
|---|---|---|---|
| vboxusers group | `sudo gpasswd -a $USER vboxusers` | `apps/virtualization.md` | universal |
| GNOME mutter experimental (dconf) | `gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'variable-refresh-rate']"` + reboot | `desktop/gnome.md` | universal |
| ASUS GPU MUX = Hybrid | `asusctl armoury set gpu_mux_mode 1` (BIOS "Display Mode = Dynamic") — **must be Hybrid or s2idle hangs** | `laptop/gpu-mux-suspend.md` | **laptop only** |
| App-launcher `.desktop` edits | Enpass/Joplin/QGIS/VirtualBox: copy to `~/.local/share/applications/` + `sed` Exec (`QT_QPA_PLATFORM=xcb` etc.) + `update-desktop-database` | `apps/{enpass,joplin,qgis,virtualization}.md` | universal (user XDG, borderline) |
| GRUB reinstall (recovery) | `sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=cachyOS`; regen | `recovery/{grub-reinstall,clone-drive}.md` | universal |

## Machine-specificity summary

- **desktop-only:** hide-amd-apu, nct6775, openrgb, powermizer autostart, rtx5090-iommu, mouse-lamzu udev, mouse-stutter i2c blacklist, system/sleep (spd5118 + asus_wmi), system/limine, mangohud-asus-ec-sensors, `/etc/environment` (NVIDIA-primary).
- **laptop-only:** amdgpu-gfx-ring-timeout udev + firmware handling, amdgpu-prevent, asus-rog, display-switching, environment-hybrid, gnome-vrr-external, gpu-mux-suspend (+ nvidia.conf S0ix), nvidia-dynamic-boost, s3-sleep (+ udev BT/LAMZU), grub-default-kernel.
- **universal:** package installs, memory tuning, `mr-pso-recompile.hook`, bluetooth base, claude-desktop, virtualbox, GRUB custom entry, split-lock sysctl, GNOME screencast autostart.

## Legacy cleanup (done 2026-07-12)

Four repo-root files were folded into the tree; two actively-wrong bullets were
deleted (Brave `radeonsi` fix — now `nvidia`; amdgpu ring-timeout "firmware
downgrade" — ruled out). `swappiness.md` was merged into `memory-tuning.md` to
kill a duplicate `vm.swappiness=10` definition. See the path note at the top.

**Audit-driven removals (2026-07-12):** a live laptop audit found the
memory-tuning doc entirely unapplied (and its systemd-oomd claim wrong —
earlyoom is the active OOM daemon here, not oomd), `vm.max_map_count` obsolete
(arch/cachy default 1048576 already exceeds the doc's 262144), and Marvel's
split-lock a CachyOS default (`/usr/lib/sysctl.d/99-splitlock.conf`). Those docs
and the split-lock section were removed; the memory / max_map rows in the tables
above are retained only as historical record.
