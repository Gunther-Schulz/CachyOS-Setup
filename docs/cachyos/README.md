# CachyOS Setup Docs

Streamlined reference from a single-source doc. **Reference:** `content/cachyos-setup/cachyos.md`.

**Systems covered (two machines):**

- **Desktop** — AMD Ryzen 9 9950X3D, ASUS ROG STRIX B850-G GAMING WIFI, RTX 5090. *(Currently down — RAM failure.)*
- **Laptop** — ASUS TUF Gaming A16 **FA607PV**: Ryzen 9 7845HX + RTX 4060 + Radeon iGPU.

**Convention:** machine-specific docs carry a `**Machine:**` tag at the top (Desktop / Laptop / Both); untagged docs apply to both. Everything in [`laptop/`](laptop/) is the laptop; [`fan-control/`](../../fan-control/) is the desktop.

## Index

| Topic | Path |
|-------|------|
| **NVIDIA** | [nvidia/](nvidia/) — [open kernel modules (switch off closed)](nvidia/open-kernel-modules.md), PowerMizer, OpenRGB, RTX 5090 + IOMMU |
| **Mouse stutter** | [mouse-stutter.md](peripherals/mouse-stutter.md) — DDC, mutter, Solaar, Bluetooth |
| **System** | [system/](system/) — Swappiness, Limine, environment, GRUB custom, [GRUB default kernel (newest, not LTS)](system/grub-default-kernel.md), vm.max_map_count |
| **Hardware** | [hardware/](hardware/) — USB NVMe, hide AMD APU, motherboard fans (nct6775) |
| **Desktop** | [desktop/](desktop/) — GNOME, VLC |
| **Apps** | [apps/](apps/) — Packages, Joplin, Conda/Mamba, Enpass, Brave, VirtualBox, QGIS, TexLive, HP Printer, Cider, [Claude Code](apps/claude-code.md), [Claude Desktop](apps/claude-desktop.md), [Discord](apps/discord.md) |
| **Peripherals** | [peripherals/](peripherals/) — LAMZU Maya X, [Bluetooth](peripherals/bluetooth.md) (incl. SMSL AO300PRO amp reconnect), [XG27JCG dual-mode](peripherals/xg27jcg-dual-mode.md) |
| **Gaming** | [gaming/](gaming/) — Proton, Steam, Lutris, PS4, Chrome flags |
| **Audio** | [audio/](audio/) — PipeWire, Helvum, Bitwig, Jamulus |
| **Laptop** | [laptop/](laptop/) — FA607PV: [NVIDIA Dynamic Boost](laptop/nvidia-dynamic-boost.md), [GPU MUX + suspend](laptop/gpu-mux-suspend.md), [display switching](laptop/display-switching.md), [hybrid /etc/environment](laptop/environment-hybrid.md), [GNOME VRR on external monitor ❌](laptop/gnome-vrr-external-monitor-hybrid.md), [amdgpu iGPU GPU reset — Electron/Chromium 🧪](laptop/amdgpu-gfx-ring-timeout.md), ASUS ROG/TUF, prevent apps using amdgpu, S3 sleep |
| **Recovery** | [recovery/](recovery/) — Clone drive, GRUB reinstall, paste logs |
| **Issues** | [issues/](issues/) — Known issues, Cursor GPU |
| **Todo** | [todo.md](todo.md) |
