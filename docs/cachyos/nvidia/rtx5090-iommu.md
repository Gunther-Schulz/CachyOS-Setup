# NVIDIA RTX 5090 (Blackwell) + AMD IOMMU Freeze

**Machine:** Desktop (RTX 5090, bare-metal AMD Ryzen 7000+).

**Problem:** freezes/hard reboots under heavy GPU load or large-model loads, with IOMMU in the default "Translated" mode.

**Cause:** the NVIDIA driver doesn't support AMD IOMMU Translated mode on bare metal for Blackwell GPUs.

**Fix:** switch IOMMU to passthrough mode (`iommu=pt`) — keeps the IOMMU active (DMA protection, VFIO/passthrough still available) but skips the translation path NVIDIA chokes on.

**Limine:** edit `/etc/default/limine`, add `iommu=pt` to the kernel cmdline, then:
```bash
sudo limine-update
sudo reboot
```

**Verify:** `sudo dmesg | grep -i "iommu: Default"` → "Passthrough". `cat /proc/cmdline | grep iommu` includes `iommu=pt`.

**Alternative (loses IOMMU protection/passthrough entirely):** `iommu=off amd_iommu=off` on the kernel cmdline.

**References:** [koboldcpp #1611](https://github.com/LostRuins/koboldcpp/issues/1611), [vLLM #22793](https://github.com/vllm-project/vllm/issues/22793).
