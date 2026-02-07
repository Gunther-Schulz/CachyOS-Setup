# GNOME Shell Suspend Before NVIDIA

For suspend/wake failures with NVIDIA + GNOME: suspend gnome-shell **before** systemd and NVIDIA suspend.

**Service:** `/etc/systemd/system/gnome-shell-suspend.service` — `Before=systemd-suspend.service`, `Before=systemd-hibernate.service`, `Before=nvidia-suspend.service`, `Before=nvidia-hibernate.service`; `ExecStart=/usr/local/bin/suspend-gnome-shell.sh suspend`; `WantedBy=systemd-suspend.service` and `systemd-hibernate.service`. Ensure script exists and is executable; `systemctl daemon-reload` and `systemctl enable gnome-shell-suspend.service`.
