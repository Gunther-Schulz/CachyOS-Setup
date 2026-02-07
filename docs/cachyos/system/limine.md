# Limine (Snapshots and Config)

**Apply config:** After editing `/etc/default/limine` or `/etc/limine-snapper-sync.conf`, run:
```bash
sudo limine-snapper-sync
```
Reboot to see boot-menu changes.

**After restoring a snapshot:** Run `sudo limine-snapper-sync` once so the menu shows current snapshots and correct default root.

### Show more snapshots in boot menu

Default is 8 entries.

1. Add to `/etc/default/limine`:
   ```bash
   echo 'MAX_SNAPSHOT_ENTRIES=30' | sudo tee -a /etc/default/limine
   ```
2. Comment out in `/etc/limine-snapper-sync.conf` so package doesn’t overwrite:
   ```bash
   sudo sed -i 's/^MAX_SNAPSHOT_ENTRIES=8/#MAX_SNAPSHOT_ENTRIES=8/' /etc/limine-snapper-sync.conf
   ```
3. `sudo limine-snapper-sync` then reboot.

**Source:** [CachyOS forum – Limine increase visible snapshot count](https://discuss.cachyos.org/t/limine-increase-visible-snaphot-count/10438).
