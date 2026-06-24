# GRUB: make the newest kernel (not LTS) the default

**Applies to:** any CachyOS **GRUB** system with *both* `linux-cachyos` and
`linux-cachyos-lts` installed. (The FA607PV laptop boots via GRUB; the desktop
uses Limine and is unaffected.)

## Symptom

GRUB boots **`linux-cachyos-lts`** by default even though you want the newest
**`linux-cachyos`**. Picking the newer kernel manually doesn't stick across
reboots, and even `GRUB_DEFAULT=0` keeps booting LTS.

## Cause — two separate things

1. **GRUB's sort ranks LTS as "newest".** `grub-mkconfig` orders the menu with a
   *reverse version sort* over the kernel filenames (`/etc/grub.d/10_linux`). The
   `-lts` suffix sorts **higher** than the bare name, so `vmlinuz-linux-cachyos-lts`
   lands **first** and becomes the top-level "simple" entry = **index 0**. So
   `GRUB_DEFAULT=0` boots LTS because index 0 *is* LTS:

   ```
   # grub-mkconfig, default ordering:
   Found linux image: /boot/vmlinuz-linux-cachyos-lts   ← index 0 (LTS!)
   Found linux image: /boot/vmlinuz-linux-cachyos
   ```

2. **`savedefault` cannot work on btrfs.** `GRUB_DEFAULT=saved`
   (+ `GRUB_SAVEDEFAULT=true`) remembers the last pick by *writing* it to
   `/boot/grub/grubenv` — but **GRUB's btrfs module is read-only at boot**, so the
   write silently fails and the default never updates. CachyOS ships
   `GRUB_DEFAULT='saved'` by default, which is why "remember my choice" looks broken
   on btrfs. (Switching bootloaders — e.g. to Limine — is *not* needed; see Fix.)
   Note: `grub-editenv` run *from Linux* can still write `grubenv` fine — only
   GRUB's own boot-time `save_env` is blocked.

## Fix — pin the main kernel to the top, boot index 0

`/etc/grub.d/10_linux` supports **`GRUB_TOP_LEVEL`**, which moves a chosen kernel to
the front of the list (making it index 0). Point it at `linux-cachyos`:

```sh
# /etc/default/grub
GRUB_DEFAULT=0                                  # boot the top entry
GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"    # force newest main kernel to the top
```

Apply (switches `GRUB_DEFAULT` from `saved` → `0`, adds `GRUB_TOP_LEVEL`, regenerates):

```sh
sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/" /etc/default/grub
echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' | sudo tee -a /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Confirm the ordering flipped — `linux-cachyos` must now be **first**:

```sh
sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep "Found linux image"
# Found linux image: /boot/vmlinuz-linux-cachyos        ← now index 0
# Found linux image: /boot/vmlinuz-linux-cachyos-lts
```

Reboot, then verify: `uname -r` → the newest `linux-cachyos`.

## Why it stays correct automatically

`/boot/vmlinuz-linux-cachyos` is **replaced in place** on every kernel update, so
`GRUB_TOP_LEVEL` always resolves to the current newest `linux-cachyos`, and the
pacman hook re-runs `grub-mkconfig` to keep it at index 0. No per-update pinning
needed. LTS stays available under **Advanced options** as the fallback.

Booting LTS manually for troubleshooting is fine — the *next* reboot returns to
the newest kernel automatically (intended; the same btrfs limitation means a
manual pick wouldn't persist anyway).
