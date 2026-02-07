# Cloning a Drive

Use [Foxclone](https://foxclone.org): download ISO, put on Ventoy USB. After clone, reinstall bootloader manually.

**Example (GRUB):** Mount root: `sudo mount -o subvol=@ /dev/nvme1n1p2 /mnt/btrfs`. Mount EFI: `sudo mount /dev/nvme1n1p1 /mnt/btrfs/boot/efi`. `sudo pacman -S arch-install-scripts`. Install GRUB: `sudo grub-install --target=x86_64-efi --efi-directory=/mnt/btrfs/boot/efi --bootloader-id=cachyOS`. Generate config: `sudo grub-mkconfig -o /mnt/btrfs/boot/grub/grub.cfg`. Adjust devices and subvol for your layout.
