# Marvel Rivals

## Audio Fix

**Issue:** Audio crackling, dropouts, or other glitches in Marvel Rivals (PipeWire).

**Fix:** Force PipeWire to a fixed sample rate and quantum before launching the game:

```bash
pw-metadata -n settings 0 clock.force-rate 48000 && pw-metadata -n settings 0 clock.force-quantum 500
```

Then start the game. Effect lasts until PipeWire is restarted.

**Revert:** Restart the audio stack to restore defaults:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

To make the fix permanent, run the `pw-metadata` command from a script or autostart when you want to play.

## Performance overlay & frame limiter

**MangoJuice** is a GUI to configure MangoHud (FPS/GPU overlay). Install with yay:

```bash
yay -S mangojuice
```

For better **1% lows**, set the frame limiter method to **early** in MangoJuice (or in MangoHud config: `fps_limit_method=early`). Set `fps_limit` **≤ your sustained floor** for flat frametimes (laptop: 74). VRR is unavailable on the laptop's external monitor (NVIDIA reports `vrr_capable=0`); the desktop has it.

## Launch options (Proton)

Both machines run Marvel Rivals (UE5) under **proton-cachyos** — set these in Steam → game **Properties → Launch Options**.

**Laptop (FA607PV):**
```
SteamDeck=1 PROTON_USE_NTSYNC=1 PROTON_DLSS_UPGRADE=1 DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_m PROTON_DLSS_INDICATOR=1 mangohud %command%
```

**Desktop (RTX 5090, 2560×1440 @ 330 Hz)** — same, plus `VKD3D_CONFIG=descriptor_heap`:
```
SteamDeck=1 PROTON_USE_NTSYNC=1 PROTON_DLSS_UPGRADE=1 VKD3D_CONFIG=descriptor_heap DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_m PROTON_DLSS_INDICATOR=1 mangohud %command%
```

| Switch | What it does |
|---|---|
| `SteamDeck=1` | **Skips the NetEase launcher** → boots straight into the game (the reason to use it). camelCase — `SteamDeck`, not `Steamdeck`. *Caveat:* can block first-time login — if login fails, remove it for one launch, then re-add. Some games apply Deck graphics defaults when they see this, but **no reports of that for Marvel Rivals** — here it's just the launcher skip. |
| `PROTON_USE_NTSYNC=1` | Uses the `ntsync` kernel sync primitive (present on CachyOS). |
| `PROTON_DLSS_UPGRADE=1` | Swaps the bundled DLSS DLL for the newer driver one (enables the transformer presets). |
| `DXVK_NVAPI_…_RENDER_PRESET_SELECTION=render_preset_m` | Forces a DLSS super-resolution preset. **Confirm it took** in the DLSS overlay — if it shows a different/default preset, the value wasn't accepted. |
| `PROTON_DLSS_INDICATOR=1` | On-screen DLSS overlay (version / render res / preset). The "UE4 generic plugin" line is DLSS *integration* metadata, not the engine — harmless. |
| `VKD3D_CONFIG=descriptor_heap` | **Desktop / RTX 5090 only.** Mitigates the Blackwell "presentation freezes 3–5 s" bug — *reduces frequency, not a cure*; experimental; benefits the 595 driver branch. Irrelevant on the laptop (Ada 4060). |
| `mangohud` | FPS/frametime overlay + frame limiter (see above). Optionally prefix `gamemoderun` to pin the CPU governor to performance for the session. |

**`PROTON_ENABLE_WAYLAND` — under evaluation.** Native Wayland is being A/B-tested for frametime impact (verdict open). Toggle trick: break the name (e.g. `_ROTON_ENABLE_WAYLAND=1`) to disable it without deleting the line. Judge it over *several* matches on a warm shader cache — single-match comparisons are dominated by shader-compile stutter and scene variance, not the flag.

**Desktop 3–5 s freezes** (RTX 5090) are an open NVIDIA **Blackwell driver bug**, not a config issue — reported across 570/575/590 drivers and every compositor. Highest-value mitigation: **toggle VRR/G-SYNC off** (it's a presentation-path bug); `VKD3D_CONFIG=descriptor_heap` reduces frequency. Track [NVIDIA open-gpu-kernel-modules #880](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/880).

**Shader-compile stutter** on first launches is normal for UE5 and smooths as the DXVK cache warms — don't judge performance on a fresh cache.
