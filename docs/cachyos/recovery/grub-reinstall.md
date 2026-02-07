# GRUB Reinstall (After Clone / Repair)

Mount root and EFI (see [clone-drive](clone-drive.md)). Install arch-install-scripts if needed. Then:

```bash
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=cachyOS
sudo grub-mkconfig -o /boot/grub/grub.cfg
```
Use your actual EFI path (e.g. `/mnt/btrfs/boot/efi` if chroot/mount differs).
