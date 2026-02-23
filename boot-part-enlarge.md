Enlarge the boot partition (proper fix)
Boot a live system (e.g. CachyOS/Arch ISO).
Use GParted: shrink root from the end (right), then grow the boot partition into the freed space.
If the boot partition UUID changes, update /etc/fstab.
The limine-snapper-sync docs recommend at least 4 GiB for the FAT32 boot partition (more if you keep many kernels/snapshots; Nvidia/DKMS can add 300+ MiB per kernel).