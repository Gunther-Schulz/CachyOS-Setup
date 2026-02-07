# Motherboard Fans and Sensors (ASUS B850-G, Ryzen 9950X3D)

Super I/O: **Nuvoton NCT6799**; kernel driver **nct6775** (read/write via ASUS WMI). Module does **not** auto-load.

**Load at boot:**
```bash
echo 'nct6775' | sudo tee /etc/modules-load.d/nct6775.conf
```
Reboot or `sudo modprobe nct6775`. Restart CoolerControl if already running: `sudo systemctl restart coolercontrold`.

**Exposed as:** `nct6799-isa-0290` in `sensors` and CoolerControl (fan1, fan2, fan7, PWM, SYSTIN, CPUTIN, AUXTIN0–5, TSI0_TEMP). Fan7 often = AIO pump. CPU temps: k10temp; RAM: spd5118.

**Manual PWM (sysfs):** Find hwmon: `find /sys/class/hwmon -name name -exec sh -c 'echo -n "$(dirname {}): "; cat {}' \;` → pick nct6799. Example for `hwmon8`/`pwm1`:
```bash
echo 1 | sudo tee /sys/class/hwmon/hwmon8/pwm1_enable
echo 128 | sudo tee /sys/class/hwmon/hwmon8/pwm1
```
Hand back to BIOS/auto: `echo 5 | sudo tee /sys/class/hwmon/hwmon8/pwm1_enable` (mode 5 = SmartFan on this board).
