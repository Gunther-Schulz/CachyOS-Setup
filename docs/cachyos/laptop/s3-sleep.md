# S3 Sleep (Asus Laptop)

**BIOS patching via GRUB (S3):** Does **not** work — patching applies but S3 sleep still fails. Reference doc has SSDT/GRUB steps for completeness.

**Show sleep modes:** `cat /sys/power/mem_sleep`.

**Temporary:** `echo deep | sudo tee /sys/power/mem_sleep` (resets after reboot).

**Permanent:** systemd oneshot service that runs `echo deep > /sys/power/mem_sleep`, `WantedBy=multi-user.target`, `After=suspend.target`. Enable and start; verify with `cat /sys/power/mem_sleep`.
