# Hide AMD Desktop APU (Integrated Graphics)

**Problem:** AMD iGPU still visible after BIOS disable (e.g. Raphael), causing GLX/ BadValue issues.

**Fix:** udev rule to remove the APU from PCI enumeration. Get IDs: `lspci -nn | grep "AMD.*Raphael"` (e.g. 1002:164e).

```bash
echo 'SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x164e", ATTR{remove}="1"' | sudo tee /etc/udev/rules.d/90-hide-amd-gpu.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo reboot
```

Replace vendor/device for your APU. Verify: `lspci | grep -i amd.*raphael` empty; `glxinfo | grep -E "(OpenGL version|OpenGL renderer)"` shows NVIDIA only.
