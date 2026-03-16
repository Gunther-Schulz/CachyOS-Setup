# Stray

Steam App ID: 1332010

## Game details

- Engine: Unreal Engine (UE4)
- Exe: `Stray-Win64-Shipping.exe` (64-bit, DX11)
- Exe directory: `~/.local/share/Steam/steamapps/common/Stray/Hk_project/Binaries/Win64/`

## ReShade setup

See [reshade.md](../reshade.md) for the full setup guide. Stray-specific notes:

- DLL override: `dxgi.dll` (auto-detected, DX11 game)
- Depth buffer works in-game but not in menus

### iMMERSE Ultimate preset

Adapted from [Amazing Raytracing (RTGI)](https://www.nexusmods.com/stray/mods/315)
by dragoncosmico, remapped from old qUINT shaders to iMMERSE Ultimate.

Effects enabled (in render order):
1. **MartysMods Launchpad** — depth/normals/motion base (required first)
2. **MartysMods RTGI Diffuse** — ray-traced global illumination (bounce lighting 2.5, AO 1.0)
3. **MartysMods MXAO** — ambient occlusion
4. **MartysMods SMAA** — anti-aliasing (prepass + main)
5. **MartysMods Sharpen** — sharpening at 0.4
6. **PD80 Filmic Adaptation** — filmic tonemapping
7. **PD80 Contrast/Brightness/Saturation** — slight contrast and saturation reduction

### Addons installed

- `MartysMods_LUTManager.addon64`
- `MartysMods_ParallaxDOF.addon64`
- `MartysMods_ReGradePlus.addon64`
