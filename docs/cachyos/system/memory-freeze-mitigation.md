# Memory Freeze Mitigation — Actionable Steps

Avoid multi-minute freezes when RAM is pressured: add disk swap (real overflow), shrink zram, tune VM, enable earlyoom. Do in this order.

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

**Not in active testing:** vm.swappiness (testing kernel default 60). **In active testing:** vm.watermark_scale_factor, vm.min_free_kbytes.

Cachyos sets **vm.swappiness = 100** in `/usr/lib/sysctl.d/70-cachyos-settings.conf`. Put overrides in `/etc/sysctl.d/` with a **higher number** (e.g. 99) so they take precedence; do not edit 70-* (vendor file, can be overwritten by updates).

**What each does:**
- **vm.swappiness = 10** — How eagerly the kernel swaps process memory. 10 = prefer freeing file cache first; 100 (Cachyos default) = treat RAM and swap equally. Lower = less push to swap, more use of cache reclaim.
- **vm.watermark_scale_factor = 100** — kswapd’s free-memory target, in 1/10000 of RAM. 100 = 1% (~600 MB on 60 GB). Default 10 = 0.1%. Higher = larger buffer = fewer allocations trigger **direct reclaim** (the thing that blocks the UI).
- **vm.min_free_kbytes = 131072** (128 MiB) — Minimum free reserve; watermarks derive from it. Slightly larger than default so you cross “below min” less often.

```bash
echo 'vm.swappiness = 10
vm.watermark_scale_factor = 100
vm.min_free_kbytes = 131072' | sudo tee /etc/sysctl.d/99-memory-freeze-mitigation.conf
sudo sysctl -p /etc/sysctl.d/99-memory-freeze-mitigation.conf
```

---

## 3. earlyoom

**In active testing.**

```bash
sudo pacman -S earlyoom
sudo systemctl enable --now earlyoom
```

---

## 4. Shrink zram (then reboot)

**In active testing.**

Cachyos (vendor) sets **zram-size = ram** in `/usr/lib/systemd/zram-generator.conf`. Override via the **admin** drop-in dir; later filename wins for same option.

With disk swap as overflow, **16–32 GiB** zram is a good range. Do **not** set zram back to `ram` (60G) because: zram stores compressed data **in RAM**, so a 60G zram can tie up a large chunk of your 60G RAM when it fills. You’d still have apps and zram competing for the same RAM; disk swap is used only when zram is full or the kernel moves pages to lower-priority swap. Smaller zram (e.g. 32G) means less RAM in the compressed pool and more pressure spilling to disk, which actually frees RAM. We avoid “all swap in RAM” situation.

```bash
sudo mkdir -p /etc/systemd/zram-generator.conf.d
echo '[zram0]
zram-size = 32G
swap-priority = 100' | sudo tee /etc/systemd/zram-generator.conf.d/90-zram-size.conf
```

Reboot so zram is recreated. After reboot: `swapon --show` should show zram0 pri 100 and disk swap pri 50.

---

## Likely impact (if everything works and swap stays low)

If you no longer get freezes and swap stays modest (e.g. &lt; 7 GB under stress), the changes that most likely mattered:

1. **Disk swap (64 GB)** — Gives real overflow out of RAM so apps and zram aren’t fighting for the same 60 GB. Pressure can go to NVMe instead of blocking in reclaim.
2. **vm.watermark_scale_factor = 100** — Keeps a ~1% free buffer so **direct reclaim** (reclaim in the faulting process → UI freeze) is triggered much less often. Probably the single setting that most reduces freezes.
3. **vm.swappiness = 10** — When the kernel needs free RAM it can either drop **file cache** (discard cached file data; can be re-read from disk later) or **swap out process memory** (write to swap = I/O, which can block). 10 = prefer dropping cache first, so the kernel frees memory without doing swap writes as often, which avoids blocking the process that asked for memory.
4. **Smaller zram (16 GB)** — With 64 GB disk swap, overflow is on disk; zram no longer competes for as much RAM.

earlyoom is a safety net; if no process ever gets killed, pressure likely never reached the point where it would have fired — the other changes kept the system away from that point.
