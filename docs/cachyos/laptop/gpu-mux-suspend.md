# GPU MUX + Suspend (FA607PV laptop)

**Machine:** Laptop (FA607PV).

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

---

## Enable NVIDIA S0ix power management (s2idle)

The panel runs on the AMD iGPU in Hybrid mode and the system only does **s2idle** (`cat /sys/power/mem_sleep` → `[s2idle]`). Tell the NVIDIA driver to enter its S0ix low-power state during s2idle:

```sh
echo 'options nvidia NVreg_EnableS0ixPowerManagement=1' | sudo tee -a /etc/modprobe.d/nvidia.conf
sudo mkinitcpio -P && sudo reboot
```

Verify after reboot (`1` = active): `cat /sys/module/nvidia/parameters/EnableS0ixPowerManagement`

Complements the already-present `NVreg_PreserveVideoMemoryAllocations=1`. It gets the dGPU into its proper low-power state during s2idle and tightens the window where the NVIDIA RM sits half-suspended — see the freeze race below.

---

## Intermittent failure: gnome-shell NVKMS mmap wedges the userspace freeze

**Distinct from the MUX hang at the top of this doc.** Even in correct Hybrid mode, suspend can *occasionally* abort one stage later, in the **userspace freeze** rather than at `PM: suspend entry`. Signature in `journalctl -b -1 -k`:

```
PM: suspend entry (s2idle)
Freezing user space processes failed after 20.0 seconds (N tasks refusing to freeze):
  task:gnome-shell  state:R  ... __nv_drm_gem_nvkms_mmap [nvidia_drm] -> rm_kernel_rmapi_op [nvidia]
  task:threaded-ml  state:D  ... do_user_addr_fault -> down_read_killable  (mmap_lock)
PM: suspend exit
```

**Cause:** NVIDIA's drop-in `/usr/lib/systemd/system/systemd-suspend.service.d/10-nvidia-no-freeze-session.conf` sets `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` so GNOME keeps running while `nvidia-suspend.service` quiesces the GPU — and gnome-shell can still issue an NVKMS `mmap()` into the half-suspended driver, wedging inside NVIDIA RM while holding the process `mmap_lock`; a sibling gnome-shell thread then blocks unkillable on the same lock, neither task freezes, and suspend aborts after the 20 s timeout (hard power-off needed). It's an upstream NVIDIA driver race, not a misconfiguration — rare, triggered by a live NVIDIA GPU surface at the instant of suspend.

Mitigations:
- `NVreg_EnableS0ixPowerManagement=1` (above) tightens the half-suspended window.
- Keep the NVIDIA driver updated (580.x branch) — these races get fixed upstream.
- **Do *not* override the no-freeze-session drop-in** to re-enable session freezing — it trades this rare race for a different, *reliable* NVIDIA deadlock that the drop-in exists to avoid.

Note: HW video decode currently runs on the dGPU (`LIBVA_DRIVER_NAME=nvidia`, following the compositor — see [environment-hybrid.md](environment-hybrid.md)), which keeps a live NVIDIA surface around and slightly raises this race's odds. The S0ix tightening is the counterweight; pinning decode back to the iGPU would reduce it but re-introduce a cross-GPU frame copy — a deliberate tradeoff, not changed here.
