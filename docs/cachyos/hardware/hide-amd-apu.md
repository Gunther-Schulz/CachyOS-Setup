# Hide AMD iGPU (Desktop)

**Machine:** Desktop.

**Problem:** the AMD iGPU (e.g. Raphael) stays visible on the PCI bus even with the BIOS iGPU disabled, causing GLX `BadValue` issues since apps can still find it alongside the NVIDIA GPU.

**Fix:** remove it from PCI enumeration via udev. Get its IDs first: `lspci -nn | grep "AMD.*Raphael"` (e.g. `1002:164e`).
```bash
echo 'SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x164e", ATTR{remove}="1"' | sudo tee /etc/udev/rules.d/90-hide-amd-gpu.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo reboot
```
Replace vendor/device IDs for your APU.

**Verify:** `lspci | grep -i amd.*raphael` → empty; `glxinfo | grep -E "(OpenGL version|OpenGL renderer)"` → NVIDIA only.

**Undo:** `sudo rm /etc/udev/rules.d/90-hide-amd-gpu.rules && sudo reboot`.
