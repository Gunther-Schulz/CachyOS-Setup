# GRUB Custom / Safety Entries

Add custom menu entries in `/etc/grub.d/40_custom`. Use a helper to resolve root device:

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

Example: Safe mode (nomodeset, nvidia and nouveau blacklisted). Adjust kernel/initrd names and UUID as needed. Then run `sudo update-grub` (or `sudo grub-mkconfig -o /boot/grub/grub.cfg`).

**Note:** Prefer systemd boot manager or Limine for new installs.
