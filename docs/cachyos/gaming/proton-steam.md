# Proton and Steam

**Proton (CachyOS):** `sudo pacman -S proton-cachyos`. GE: `sudo pacman -S proton-ge-custom`. Wayland: add `PROTON_ENABLE_WAYLAND=1 %command%` to game launch options.

**Steam:** `sudo pacman -S steam`. If in-game lag after ~45 min: disable GPU-accelerated web view in Steam → Interface. If lag on notifications: add `LD_PRELOAD=" " %command%` to launch; optionally `PROTON_USE_WINED3D=1` ([dxvk #4436](https://github.com/doitsujin/dxvk/issues/4436)).

**PS4 controller:** Settings → Controller → enable "Enable Steam Input for generic controllers". No extra driver needed. Troubleshooting: reset button on back; check `ls -l /dev/input/js*`.
