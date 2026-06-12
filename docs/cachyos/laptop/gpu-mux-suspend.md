# GPU MUX + Suspend (FA607PV laptop)

The ASUS TUF A16 (FA607PV: Ryzen 9 7845HX + RTX 4060 + AMD Raphael iGPU) only supports **s2idle** (no S3 — see [s3-sleep.md](s3-sleep.md)). Suspend **hangs on the way into sleep** (freezes at `PM: suspend entry`, never resumes, needs a hard power-off) whenever the GPU MUX is in **dGPU/Ultimate mode** — the panel is hardwired to the NVIDIA card, which then can't power down for s2idle.

**Fix: run the GPU in Hybrid mode** (panel on the AMD iGPU, NVIDIA on-demand and able to suspend).

**Check current mode** (`1` = Hybrid ✅, `0` = dGPU-only ❌):
```sh
asusctl armoury get gpu_mux_mode
# or:
cat /sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value
```

**Set Hybrid:**
```sh
asusctl armoury set gpu_mux_mode 1
# or: echo 1 | sudo tee /sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value
```

- ⚠️ **The change only applies on the next reboot.** Right after setting it, the value still *reads back* the old one — that's expected (it's staged, not rejected). Reboot, then re-check; it should read `1`.
- BIOS **"Display Mode" must be "Dynamic"** (not "dGPU only") for Hybrid to be allowed.
- Confirm the panel moved to the iGPU after reboot: `cat /sys/class/drm/card*/device/boot_vga` (amdgpu card should be `1`), and `cat /sys/class/drm/*-eDP*/status` (eDP connected on the amdgpu card).

**Tradeoff vs [amdgpu-prevent.md](amdgpu-prevent.md):** that doc's "dGPU only in BIOS" approach (apps default to NVIDIA) is the *opposite* of this and **breaks suspend**. Pick one:
- **Suspend matters** → Hybrid (this doc). Apps then default to the iGPU; force NVIDIA per-app with `prime-run <app>` or `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>`.
- **Effortless dGPU-for-everything matters more than suspend** → dGPU-only, and don't rely on suspend.
