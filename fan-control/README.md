# Fan Control (WIP — desktop: ASUS B850-G / Ryzen 9950X3D)

Working area for tuning the desktop fan curve via **CoolerControl**. This is scratch/iterate space, not polished reference — build the fan-curve work off these.

- **`coolercontrol-labels.md`** — how to set human-readable device/channel labels via the CoolerControl REST API, **plus a reference table of this system's actual fan/temp labels** (NCT6799, Silent Loop 3, P12) and the NCT6799 device UID.
- **`coolercontrol-fans-100.sh [1|2|both]`** — force motherboard (NCT6799) fans to 100% via the CC API.
- **`coolercontrol-fans-revert.sh [1|2|both]`** — restore the Default Profile.

CoolerControl API: `http://localhost:11987` (default login `CCAdmin` / `coolAdmin`). Background on the sensors/driver: [docs › motherboard-fans](../docs/cachyos/hardware/motherboard-fans.md).
