# Setting Human-Readable Labels in CoolerControl

Two places must be updated so labels persist and show in the GUI.

## 1. Daemon device settings (persisted in daemon config)

- **Endpoint:** `PUT /settings/devices/{device_uid}`
- **Auth:** Session cookie after `POST /login` (Basic `CCAdmin` / password, default `coolAdmin`)
- **Body (JSON):** `name`, `disable`, `extensions`, `channel_settings`
  - `name`: device display name (e.g. `"Motherboard (NCT6799)"`)
  - `channel_settings`: map of channel name → `{ "disabled": false, "label": "Human Label", "extension": null }`
- **Example:** Set device name and channel labels (fans, temps) per device. Keep existing `disable` and `extensions` from `GET /settings/devices`.

## 2. UI config (what the GUI tree displays)

- **Get:** `GET /settings/ui` → JSON with `devices` (array of UIDs) and `deviceSettings` (same order).
- **Edit:** For each device: set `deviceSettings[i].userName` to the device name. For each channel: set `deviceSettings[i].sensorAndChannelSettings[j].userName` to the channel label, where `j` is the index of that channel in `deviceSettings[i].names`.
- **Save:** `PUT /settings/ui` with the full modified JSON (e.g. `Content-Type: application/json`).

## Procedure (concise)

1. Login: `POST /login` with Basic auth, save session cookie.
2. **Daemon:** For each device, `GET /settings/devices` to get current payload, then `PUT /settings/devices/{uid}` with updated `name` and `channel_settings` (only add/change `label`; keep `disabled: false`, `extension: null`).
3. **UI:** `GET /settings/ui` → parse JSON → set `deviceSettings[i].userName` and `deviceSettings[i].sensorAndChannelSettings[j].userName` for each device/channel → `PUT /settings/ui` with full JSON.
4. Reload the GUI (browser refresh or reopen app) to see labels.

Base URL: `http://localhost:11987` (or `https://` if TLS is enabled).

---

## Reference: labels used on this system (ASUS B850-G, NCT6799, Silent Loop 3, P12)

**Device names**

| Device (source) | Display name |
|-----------------|---------------|
| nct6799 | Motherboard (NCT6799) |
| CPU (Ryzen 9950X3D) | CPU (Ryzen 9950X3D) |
| RTX 5090 | GPU (RTX 5090) |
| amdgpu | iGPU (Radeon) |
| spd5118 (×2) | RAM Temp (DIMM A) / RAM Temp (DIMM B) |
| Samsung NVMe | Samsung SSD 990 PRO 4TB / 2TB, Samsung SSD 9100 PRO 4TB |

**Motherboard (NCT6799) channel labels**

| Channel | Label | Notes |
|---------|--------|--------|
| fan1 | P12 (RPM 2×) | Arctic P12; header reports 2 tach pulses/rev so displayed RPM is ~2× actual (P12 max 1800). Cannot fix via `/etc/sensors.d/` — NCT6799 has no fan divisor; only NCT6775F does. See `sensors.d-fan-rpm-fix.conf` for reference. |
| fan2 | Silent Wings 4 (AIO) | Be Quiet Silent Loop 3 radiator fans; RPM display correct. |
| fan3, fan4, fan5 | Aux Fan 3 / 4 / 5 | Extra chassis/optional headers; 0 rpm = unused or no tach. |
| fan7 | AIO Pump | Silent Loop 3 pump. |
| temp1 | System | SYSTIN (system temp). |
| temp2 | CPU socket | CPUTIN (socket thermistor). |
| temp3–temp7 | Aux 0 … Aux 4 | AUXTIN0–AUXTIN4 (board aux sensors). |
| temp8 | PECI/TSI cal | PECI/TSI Agent 0 Calibration. |
| temp9 | Aux 5 | AUXTIN5. |
| temp10–temp12 | PCH max (unused), PCH chip (unused), PCH CPU (unused) | PCH temps; 0 °C on AMD. |
| temp13 | CPU | TSI0_TEMP (main CPU temp via AMD TSI). |

**Note:** Kernel names are in `/sys/class/hwmon/hwmon*/temp*_label` (nct6799). Use those for exact driver names; the table above uses human-readable labels derived from them.

**CPU:** temp1 → Tctl, temp3 → Tccd1, temp4 → Tccd2.  
**GPU:** fan1/fan2 → GPU Fan 1 / GPU Fan 2.  
**NVMe:** temp1/2/3 → Composite, Sensor 1, Sensor 2.  
**RAM (spd5118):** temp1 → DIMM.
