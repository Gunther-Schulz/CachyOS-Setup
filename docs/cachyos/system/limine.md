# Limine (Snapshots and Config)

**Apply config:** After editing `/etc/default/limine` or `/etc/limine-snapper-sync.conf`, run:
```bash
sudo limine-snapper-sync
```
Reboot to see boot-menu changes.

**After restoring a snapshot:** Run `sudo limine-snapper-sync` once so the menu shows current snapshots and correct default root.

### Snapshot count

Keep the default (8). The real constraint is `/boot` space — more snapshots need a bigger boot partition (NVIDIA/DKMS kernels are large). **TODO (desktop):** enlarge the boot partition so more snapshots fit — see [recovery/boot-part-enlarge.md](../recovery/boot-part-enlarge.md).
