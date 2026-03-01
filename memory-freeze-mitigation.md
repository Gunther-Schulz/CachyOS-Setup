# Memory Freeze Mitigation — Actionable Steps

Avoid multi-minute freezes when RAM is pressured: add disk swap (real overflow), shrink zram, tune VM, enable systemd-oomd with a short pressure duration on the user session. Do in this order.

**Swap priority:** zram = 100, disk = 50 (higher = used first). Kernel uses zram first, then disk when zram is full or as overflow.

---

## 1. Add disk swap (64 GiB)

**In active testing.**

**On ext4** (e.g. `/mnt/data2t`):

```bash
sudo dd if=/dev/zero of=/mnt/data2t/swapfile bs=1M count=65536 status=progress
sudo chmod 0600 /mnt/data2t/swapfile
sudo mkswap /mnt/data2t/swapfile
sudo swapon -p 50 /mnt/data2t/swapfile
echo '/mnt/data2t/swapfile none swap pri=50 0 0' | sudo tee -a /etc/fstab
```

**On Btrfs root** (NoCOW; set `+C` before allocating):

```bash
sudo truncate -s 0 /swapfile
sudo chattr +C /swapfile
sudo fallocate -l 64G /swapfile
sudo chmod 0600 /swapfile
sudo mkswap /swapfile
sudo swapon -p 50 /swapfile
echo '/swapfile none swap pri=50 0 0' | sudo tee -a /etc/fstab
```

(Btrfs: don’t snapshot the subvolume that contains the swap file.)

---

## 2. VM tuning (persist + apply)

**Current settings (in use):** vm.swappiness = 10, vm.watermark_scale_factor = 100, vm.min_free_kbytes = 131072.

Cachyos sets **vm.swappiness = 100** in `/usr/lib/sysctl.d/70-cachyos-settings.conf`. Overrides in `/etc/sysctl.d/` take precedence; do not edit 70-* (vendor file).

**What each does:**
- **vm.swappiness = 10** — How eagerly the kernel swaps process memory. 10 = prefer freeing file cache first; 100 (Cachyos default) = treat RAM and swap equally.
- **vm.watermark_scale_factor = 100** — kswapd’s free-memory target, in 1/10000 of RAM. 100 = 1% (~600 MB on 60 GB). Higher = larger buffer = fewer allocations trigger **direct reclaim** (the thing that blocks the UI).
- **vm.min_free_kbytes = 131072** (128 MiB) — Minimum free reserve; watermarks derive from it.

**File:** `/etc/sysctl.d/99-memory-freeze-mitigation.conf`:

```
vm.watermark_scale_factor = 100
vm.min_free_kbytes = 131072
vm.swappiness = 10
```

Apply: `sudo sysctl -p /etc/sysctl.d/99-memory-freeze-mitigation.conf`

---

## 3. Userspace OOM killer

**In active testing.**

The system uses **systemd-oomd** as the userspace OOM killer; **earlyoom is disabled**.

- `systemd-oomd.service` and `systemd-oomd.socket` are **enabled**.
- `earlyoom.service` is **disabled**.

**Critical:** For oomd to act before a freeze, the **duration** must be short. The default is 30 seconds — pressure must stay above the limit for 30s before oomd kills. Freezes happen in seconds, so nothing gets killed. Set a drop-in for your user session with **ManagedOOMMemoryPressureDurationSec=3** (or 1–2 if you want it to act even sooner).

**`/etc/systemd/system/user@1000.service.d/override.conf`** (create via `sudo systemctl edit user@1000.service`):

```ini
[Service]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=20%
ManagedOOMMemoryPressureDurationSec=3
```

- **ManagedOOMMemoryPressureLimit=20%** — Act when PSI memory pressure for the session is above 20% (lower = act earlier).
- **ManagedOOMMemoryPressureDurationSec=3** — Require that pressure for **3 seconds** before killing a descendant cgroup. Default is ~30s; 1–3s is the range that works so oomd fires before the UI freezes.

After editing: `sudo systemctl daemon-reload`. Verify with `systemctl show user@1000.service | grep ManagedOOM`.

Under memory stress, systemd-oomd will now kill a heavy child cgroup (e.g. browser or stress process) instead of the whole session freezing.

---

## 4. Shrink zram (then reboot)

**In active testing.**

Cachyos (vendor) sets **zram-size = ram** in `/usr/lib/systemd/zram-generator.conf`. Override via the **admin** drop-in dir: **`/etc/systemd/zram-generator.conf.d/`** (note: `zram-generator.conf.d`, not `zram-generator.d`). Later filename wins for same option.

With disk swap as overflow, **16–32 GiB** zram is a good range. Do **not** set zram back to `ram` (60G) because: zram stores compressed data **in RAM**, so a 60G zram can tie up a large chunk of your 60G RAM when it fills. You’d still have apps and zram competing for the same RAM; disk swap is used only when zram is full or the kernel moves pages to lower-priority swap. Smaller zram (e.g. 32G) means less RAM in the compressed pool and more pressure spilling to disk, which actually frees RAM. We avoid “all swap in RAM” situation.

```bash
sudo mkdir -p /etc/systemd/zram-generator.conf.d
echo '[zram0]
zram-size = 24576
swap-priority = 100' | sudo tee /etc/systemd/zram-generator.conf.d/90-zram-size.conf
```

(32768 MB = 32 GiB; using MB avoids parser bugs that can cause vmalloc errors with `32G`.) Then `sudo systemctl daemon-reload` and reboot.

Reboot so zram is recreated. After reboot: `swapon --show` should show zram0 pri 100 and disk swap pri 50. To confirm zram isn’t failing: `journalctl -b -k --no-pager | grep -i zram` should show no “vmalloc error” or “exceeds total pages”.

---

## Likely impact (if everything works and swap stays low)

If you no longer get freezes and swap stays modest (e.g. &lt; 7 GB under stress), the changes that most likely mattered:

1. **Disk swap (64 GB)** — Gives real overflow out of RAM so apps and zram aren’t fighting for the same 60 GB. Pressure can go to NVMe instead of blocking in reclaim.
2. **vm.watermark_scale_factor = 100** — Keeps a ~1% free buffer so **direct reclaim** (reclaim in the faulting process → UI freeze) is triggered much less often.
3. **vm.swappiness** — Tune for your workload (e.g. 10 for more file-cache reclaim, or 20–60 if process-memory pressure is high so kswapd uses swap more proactively).
4. **Smaller zram (e.g. 24–32 GiB)** — With 64 GB disk swap, overflow is on disk; zram no longer competes for as much RAM.
5. **systemd-oomd + short duration** — With `ManagedOOMMemoryPressure=kill`, `ManagedOOMMemoryPressureLimit=20%`, and **ManagedOOMMemoryPressureDurationSec=3** on `user@1000.service`, oomd kills a heavy cgroup after ~3s of high pressure instead of 30s, so the session stays responsive instead of freezing.

Optional: run known-heavy workloads in a memory-limited scope so only that scope can be killed: `systemd-run --user --scope -p MemoryMax=40G -p MemorySwapMax=0 -- your_command`

---

## If the session still dies (e.g. logout / display crash)

If `user@1000.service` shows “Main process exited, code=killed, status=9/KILL” and the whole session tears down, check whether the OOM killer was the cause:

```bash
journalctl -b -k --no-pager | grep -i -E 'oom|killed process|out of memory'
```

If you see “Killed process …” for a large consumer, the kernel ran out of memory and killed it (often the session leader). Fixing zram (so it doesn’t vmalloc-fail) and keeping a sane zram size plus disk swap and VM tuning should reduce how often that happens. Optionally run heavy workloads (e.g. vLLM) in a cgroup with a memory limit so the kernel kills that scope instead of the whole session.
