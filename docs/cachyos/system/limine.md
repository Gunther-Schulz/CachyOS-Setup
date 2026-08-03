# Limine (Snapshots and Config)

**Apply config:** After editing `/etc/default/limine` or `/etc/limine-snapper-sync.conf`, run:
```bash
sudo limine-snapper-sync
```
Reboot to see boot-menu changes.

**After restoring a snapshot:** Run `sudo limine-snapper-sync` once so the menu shows current snapshots and correct default root.

### Don't enable Secure Boot on this setup

**Decided 2026-08-03: leave Secure Boot disabled.** It has to be off to install
CachyOS at all ([archiso has had no SB support since 2016](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Booting_an_installation_medium);
[CachyOS docs](https://wiki.cachyos.org/configuration/secure_boot_setup/) cover only
post-install enabling), and re-enabling it afterwards is a bad trade **here
specifically** — not in general:

- **It attacks the recovery path.** Limine's config-integrity feature hashes
  kernel/initramfs paths (BLAKE2B) into `limine.conf`, and every kernel or
  snapshot update staleness them. A CachyOS user hit
  [`PANIC: Blake2b hash mismatch`, unbootable **even after turning Secure Boot
  back off**](https://discuss.cachyos.org/t/is-there-a-solution-for-making-secure-boot-work-with-limine-snapshots/8148) —
  recovery needed external rescue media. The snapshot boot menu is this
  machine's rollback story; SB puts it at risk to protect it.
- **NVIDIA modules are unresolved on CachyOS.** `sbctl` signs EFI binaries only,
  [not kernel modules](https://bbs.archlinux.org/viewtopic.php?id=290866); CachyOS's
  kernel lacked `CONFIG_INTEGRITY_CA_MACHINE_KEYRING`, so even correctly MOK-signed
  DKMS modules failed under `lockdown=integrity`
  ([#743](https://github.com/CachyOS/linux-cachyos/issues/743), closed "not planned";
  IMA-based fix [#862](https://github.com/CachyOS/linux-cachyos/issues/862) still open).
- **The benefit is narrow without FDE.** No full-disk encryption means physical
  access reads the drive directly regardless; no TPM-sealed secrets means no
  measured-boot assurance. SB would buy anti-bootkit-persistence only.

**Re-open if** full-disk encryption gets added (then the threat model changes and
SB becomes worth its cost), or if CachyOS ships the machine-keyring fix and
`limine-snapper-sync` gains hash re-enrollment.

### Snapshot count

Keep the default (8). The real constraint is `/boot` space — more snapshots need a bigger boot partition (NVIDIA/DKMS kernels are large). **TODO (desktop):** enlarge the boot partition so more snapshots fit — see [recovery/boot-part-enlarge.md](../recovery/boot-part-enlarge.md).
