# NVIDIA RTX 5090 (Blackwell) + AMD IOMMU

**Problem:** RTX 5090 (and other Blackwell) can cause freezes/hard reboots when loading large models or heavy GPU load on bare-metal AMD (Ryzen 7000+) with IOMMU in default "Translated" mode.

**Cause:** NVIDIA drivers don’t support AMD IOMMU in Translated mode on bare metal.

**Fix:** Enable IOMMU passthrough: `iommu=pt`.

**Limine:** Edit `/etc/default/limine`, add `iommu=pt` to kernel cmdline, then:
```bash
sudo limine-update
sudo reboot
```

**Verify:** `sudo dmesg | grep -i "iommu: Default"` → "Passthrough". `cat /proc/cmdline | grep iommu` includes `iommu=pt`.

**Alternative:** Disable IOMMU: add `iommu=off amd_iommu=off` to kernel cmdline.

**References:** [koboldcpp #1611](https://github.com/LostRuins/koboldcpp/issues/1611), [vLLM #22793](https://github.com/vllm-project/vllm/issues/22793).
