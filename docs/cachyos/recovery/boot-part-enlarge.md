# Enlarge the boot partition

Proper fix (not a workaround):

1. Boot a live system (e.g. CachyOS/Arch ISO).
2. In GParted, shrink root from the end (right), then grow the boot partition into the freed space.
3. If the boot partition UUID changes, update `/etc/fstab`.

The limine-snapper-sync docs recommend **≥ 4 GiB** for the FAT32 boot partition (more if you keep many kernels/snapshots — NVIDIA/DKMS can add 300+ MiB per kernel).
