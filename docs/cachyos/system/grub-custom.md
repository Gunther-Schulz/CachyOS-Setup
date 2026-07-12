# GRUB Custom / Safety Boot Entries

**Machine:** Laptop (GRUB) — desktop boots Limine, see [grub-default-kernel.md](grub-default-kernel.md).

Add one-off recovery entries (e.g. a `nomodeset` safe-mode boot) to `/etc/grub.d/40_custom` — GRUB reads it verbatim and appends it to the generated menu. Resolve the root device the same way `10_linux` does, so the entry survives UUID changes:

```bash
get_root_device() {
    if ( [ "x${GRUB_DEVICE_UUID}" = "x" ] && [ "x${GRUB_DEVICE_PARTUUID}" = "x" ] ) \
        || ( [ "x${GRUB_DISABLE_LINUX_UUID}" = "xtrue" ] && [ "x${GRUB_DISABLE_LINUX_PARTUUID}" = "xtrue" ] ) \
        || ( ! test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}" && ! test -e "/dev/disk/by-partuuid/${GRUB_DEVICE_PARTUUID}" ) \
        || ( test -e "${GRUB_DEVICE}" && uses_abstraction "${GRUB_DEVICE}" lvm ); then
      echo ${GRUB_DEVICE}
    elif [ "x${GRUB_DEVICE_UUID}" = "x" ] || [ "x${GRUB_DISABLE_LINUX_UUID}" = "xtrue" ]; then
      echo PARTUUID=${GRUB_DEVICE_PARTUUID}
    else
      echo UUID=${GRUB_DEVICE_UUID}
    fi
}
```

After adding an entry: `sudo grub-mkconfig -o /boot/grub/grub.cfg` (or `sudo update-grub`).

**Status:** not currently applied — `/etc/grub.d/40_custom` is stock (verified). Kept as a break-glass reference.
