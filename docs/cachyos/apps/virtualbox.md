# VirtualBox

**Install:** `sudo pacman -S virtualbox virtualbox-host-dkms virtualbox-guest-iso virtualbox-guest-utils`. Optional: `yay -S virtualbox-ext-oracle vbox-windows-app-launcher-git`. `sudo gpasswd -a $USER vboxusers`, `sudo modprobe vboxdrv`.

**Register copied VM:** `VBoxManage registervm "$HOME/VirtualBox VMs/Win11/Win11.vbox"`. Update shared folder host path if username differs.

**Blacklist KVM (required on some kernels):**
```bash
echo "blacklist kvm" | sudo tee /etc/modprobe.d/kvm.conf
echo "blacklist kvm_amd" | sudo tee /etc/modprobe.d/kvm_amd.conf
```

**Windows 11 OOBE:** Disable networking in VM. At "Let's connect you to a network", Shift+F10 → `OOBE\BYPASSNRO` → restart → "I don't have Internet" → limited setup.

**Config:** Enable VT-x/AMD-V, PAE/NX. For AutoCAD: disable 3D acceleration in VM.

**Taskbar (GNOME):** Copy desktop file, add `StartupWMClass=VirtualBox Machine` so VM windows group under same icon.

**Troubleshooting:** Correct linux-headers for kernel; `sudo vboxreload` after updates. If password not accepted at Win11 login, wait a few minutes and retry.
