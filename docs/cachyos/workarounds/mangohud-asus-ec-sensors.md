# MangoHUD

**Install:** `sudo pacman -S mangohud lib32-mangohud`. Config via MangoJuice: `yay -S mangojuice`.

**Crashes on launch (asus_ec_sensors bug):** MangoHUD calls `stoi` on empty hwmon reads from `asus_ec_sensors` when those sensor files return I/O errors, causing an abort. Fix: blacklist the module so MangoHUD falls back to `k10temp`.
```bash
echo "blacklist asus_ec_sensors" | sudo tee /etc/modprobe.d/blacklist-asus-ec-sensors.conf
sudo modprobe -r asus_ec_sensors
```

**Revert (once fixed upstream):**
```bash
sudo rm /etc/modprobe.d/blacklist-asus-ec-sensors.conf
sudo modprobe asus_ec_sensors
```
