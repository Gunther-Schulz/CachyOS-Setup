# Cloning a Drive

Use [Foxclone](https://foxclone.org): download the ISO, put it on a Ventoy USB. Bootloader isn't cloned — reinstall it manually afterward.

**Example (GRUB, btrfs root):**
```bash
sudo mount -o subvol=@ /dev/nvme1n1p2 /mnt/btrfs
sudo mount /dev/nvme1n1p1 /mnt/btrfs/boot/efi
sudo pacman -S arch-install-scripts
sudo grub-install --target=x86_64-efi --efi-directory=/mnt/btrfs/boot/efi --bootloader-id=cachyOS
sudo grub-mkconfig -o /mnt/btrfs/boot/grub/grub.cfg
```
Adjust devices and subvolume for your layout.
