# Known Issues

- Sometimes wont sleep/sleep for a few seconds then wake.
- When sleeping audi interface will diconeect. Have to re-plug USB
- RGB not restored after sleep
- Enlarge /boot from live USB
- Undervolt
- PBO Off?

**Grey screen in GDM, stuck cursor, Ctrl+Alt+F1 not working:** Often dual-monitor. Disconnect second monitor and login dialog appears.

**Double key press in GRUB menu:** Seen on 4K Acer; disconnecting it forces display to Dell 2K where input is slow but works. Try: lower `GRUB_GFXMODE` (e.g. 1280x1024x32) in `/etc/default/grub`, `sudo update-grub`; disable CSM in BIOS.

**Chromium/Wayland:** `ERROR:wayland_frame_manager.cc(627)] The server has buggy presentation feedback...` — known Chromium-on-Wayland diagnostic; safe to ignore, no fix needed.

**NVIDIA GSP-RM heartbeat timeout on S3 resume (RTX 5090, driver 595.45.04):** System freezes ~1s after waking from S3 deep sleep. Kernel logs show `NVRM: _kgspIsHeartbeatTimedOut: Heartbeat timed out` and `NVRM: _kgspRpcRecvPoll: GSP RM heartbeat timed out`. Requires hard power cycle. First observed 2026-03-16. Config is correct per NVIDIA docs (open kernel module, `UseKernelSuspendNotifiers=1`, systemd services correctly disabled). Known driver bug — NVIDIA engineer acknowledged in [595.45.04 suspend crash thread](https://forums.developer.nvidia.com/t/system-crashes-on-suspend-with-595-45-04/363397). Also reported for RTX 5090 specifically in [monitor resume failure thread](https://forums.developer.nvidia.com/t/failure-to-resume-wake-up-monitors-on-rtx-5090/357550). No workaround confirmed yet; monitor for newer driver releases. **s2idle is not a fix** — this system has no S0ix platform support (`/proc/driver/nvidia/gpus/0000:01:00.0/power` reports both S0ix Platform Support and Video Memory Self Refresh as "Not Supported"). Other Blackwell users report s2idle also fails but differently: displays don't wake ("Pageflip timed out" in nvidia-drm), though the system stays alive via SSH and can be recovered by restarting the display manager ([RTX 5070 Ti on CachyOS](https://forums.developer.nvidia.com/t/rtx-5070-ti-blackwell-gb203-pageflip-timeout-on-resume-from-s2idle-suspend-displays-fail-to-wake/359674), [RTX 5090 s2idle vs S3](https://forums.developer.nvidia.com/t/580-release-feedback-discussion/341205/1035)). S3 causes a hard lock; s2idle causes a soft display failure — neither works correctly. Note: `NVreg_EnableS0ixPowerManagement=1` in `/usr/lib/modprobe.d/nvidia.conf` (from `cachyos-settings`) is a no-op on this hardware.
