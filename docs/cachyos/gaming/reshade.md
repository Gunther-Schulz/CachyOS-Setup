# ReShade on CachyOS (Steam/Proton)

Guide for setting up ReShade with iMMERSE shaders on Steam games via Proton.
Uses Stray (App ID: 1332010) as example throughout.

## 1. Install reshade-steam-proton from AUR

```fish
yay -S reshade-steam-proton-git
```

This provides `reshade-steam-proton.sh`, which downloads ReShade and base shader repos,
symlinks them into game directories, and handles the d3dcompiler_47 DLL override via protontricks.

Dependencies: `curl`, `7z`, `wget`, `protontricks`, `git`.

## 2. Run the game at least once

Launch the game through Steam so Proton creates the required Wine prefix and directories.
Exit after reaching the menu.

## 3. Find the game's exe directory

In Steam: right-click game > Properties > Local Files > Browse. Find the directory containing the main `.exe`.

For Stray:
```
~/.local/share/Steam/steamapps/common/Stray/Hk_project/Binaries/Win64/
```

The actual exe is `Stray-Win64-Shipping.exe` (64-bit, DX11).

## 4. Run reshade-steam-proton.sh

```fish
reshade-steam-proton.sh
```

Interactive prompts:
1. Type `i` to install
2. Paste the game exe directory path
3. Select automatic DLL detection (it will pick `dxgi.dll` for DX10/11/12 games)
4. Enter the Steam App ID: `1332010`

The script:
- Downloads ReShade and shader repos to `~/.local/share/reshade/`
- Symlinks `dxgi.dll` -> ReShade64.dll into the game's exe directory
- Copies `d3dcompiler_47.dll` via protontricks
- Clones shader repos (reshade-shaders, sweetfx, prod80, etc.) into `~/.local/share/reshade/ReShade_shaders/`
- Merges all shaders into `~/.local/share/reshade/ReShade_shaders/Merged/`

## 5. First launch with ReShade

Launch the game. ReShade overlay opens on first run (toggle with `Home` key).

In ReShade settings, verify these paths are set:
- **Effect search paths:** `Z:\home\g\.local\share\reshade\ReShade_shaders\Merged\Shaders`
- **Texture search paths:** `Z:\home\g\.local\share\reshade\ReShade_shaders\Merged\Textures`

The `Z:\` prefix is the Wine drive mapping for `/`.

## 6. Install iMMERSE Ultimate (paid shaders)

iMMERSE Ultimate (by Pascal Gilcher / MartysMods) includes RTGI, Relight, Parallax DOF, and more.
Download from the Patreon Discord (requires Patreon subscription + Discord linked).

### Extract and install

The zip contains three directories: `Shaders/`, `Textures/`, `Addons/`.

**Shaders and Textures** go into the shared Merged directory (works for all games):

```fish
set ZIP ~/Downloads/"iMMERSE Ultimate_2603.zip"  # adjust version
set MERGED ~/.local/share/reshade/ReShade_shaders/Merged

unzip -o $ZIP "Shaders/*" -d /tmp/immerse-ultimate
unzip -o $ZIP "Textures/*" -d /tmp/immerse-ultimate

cp -r /tmp/immerse-ultimate/Shaders/iMMERSE $MERGED/Shaders/
cp -r /tmp/immerse-ultimate/Textures/iMMERSE $MERGED/Textures/
```

**Addons** (`.addon64` for 64-bit games) go into the game's exe directory (per-game):

```fish
set GAMEDIR ~/.local/share/Steam/steamapps/common/Stray/Hk_project/Binaries/Win64
unzip -o $ZIP "Addons/*addon64" -d /tmp/immerse-ultimate
cp /tmp/immerse-ultimate/Addons/*addon64 $GAMEDIR/
```

For 32-bit games, use `*addon32` instead.

### Remove old qUINT shaders

iMMERSE supersedes the older qUINT shaders (qUINT_mxao, qUINT_bloom, etc.).
Remove them from Merged to avoid duplicate/conflicting effects:

```fish
rm ~/.local/share/reshade/ReShade_shaders/Merged/Shaders/qUINT_*
```

### Verify

Launch the game, open ReShade overlay (`Home`), and the iMMERSE effects should appear
in the effect list (MartysMods_RTGI_DIFFUSE, MartysMods_RELIGHT, etc.).

## 7. Presets

Presets are `.ini` files that define which effects are enabled and their settings.
They go in the game's exe directory as `ReShadePreset.ini` (or any name — selectable
in the ReShade overlay dropdown).

### Finding presets

- **Nexus Mods** — game-specific presets, but most are built for old free shaders (qUINT).
  These won't work with iMMERSE Ultimate without remapping effect names.
- **MartysMods Discord (#shader-gallery)** — showcase channel, not direct downloads.
  Presets for iMMERSE Ultimate are typically configured manually in-game.
- **Manual** — enable effects in the ReShade overlay and tweak to taste. This is the
  most common workflow for iMMERSE Ultimate since the shaders are newer and presets
  from Nexus reference old qUINT technique/parameter names.

### Adapting old qUINT presets for iMMERSE Ultimate

Old presets reference `qUINT_rtgi.fx`, `qUINT_mxao.fx`, etc. Key mappings:

| Old (qUINT)              | New (iMMERSE Ultimate)                    |
|--------------------------|-------------------------------------------|
| `qUINT_rtgi.fx`          | `iMMERSE\MartysMods_RTGI_DIFFUSE.fx`     |
| `qUINT_mxao.fx`          | `iMMERSE\MartysMods_MXAO.fx`             |
| `qUINT_bloom.fx`         | `iMMERSE\MartysMods_SOLARIS.fx`           |
| `qUINT_sharp.fx`         | `iMMERSE\MartysMods_SHARPEN.fx`           |
| `qUINT_dof.fx`           | `iMMERSE\MartysMods_DEPTHOFFIELD.fx`      |
| `qUINT_lightroom.fx`     | `iMMERSE\MartysMods_REGRADE.fx`           |
| `qUINT_deband.fx`        | (no direct replacement)                   |
| `qUINT_ssr.fx`           | `iMMERSE\MartysMods_RTGI_SPECULAR.fx`     |
| FXAA.fx                  | `iMMERSE\MartysMods_SMAA.fx`              |

Parameter names have also changed between qUINT and iMMERSE, so settings don't carry
over 1:1 — use old values as a rough guide and tweak in-game.

**Important:** iMMERSE effects require `MartysMods_LAUNCHPAD` to be first in the
technique sorting order. It provides depth, normals, and motion data to all other
iMMERSE effects.

### Preset structure

A `ReShadePreset.ini` looks like:

```ini
Techniques=MartysMods_Launchpad@iMMERSE\MartysMods_LAUNCHPAD.fx,MartysMods_NEWGI_Diffuse@iMMERSE\MartysMods_RTGI_DIFFUSE.fx,...
TechniqueSorting=<same as Techniques — defines render order>

[iMMERSE\MartysMods_RTGI_DIFFUSE.fx]
RT_IL_AMOUNT=2.500000
...
```

Format: `TechniqueName@path\to\shader.fx` — paths are relative to the shader search directory.

## 8. Depth buffer troubleshooting

Some games (especially in menus) don't expose the depth buffer correctly. If effects
look flat or don't work:

1. Open ReShade overlay (`Home`)
2. Enable `DisplayDepth` shader
3. Left half should show colors, right half greyscale depth — if right side is black:
   - Go to **Add-ons** tab, cycle through available depth buffers until one works
   - Or go to **Home**, disable Performance Mode, click "Edit global preprocessor
     definitions", toggle `RESHADE_DEPTH_IS_REVERSED` between 0 and 1
4. **Must be in-game** (not main menu) for depth buffer to be available
5. Once working, disable `DisplayDepth` and re-enable Performance Mode

## Directory structure reference

```
~/.local/share/reshade/
├── reshade/6.7.3/ReShade64.dll      # ReShade binary (symlinked as dxgi.dll into games)
├── ReShade_shaders/
│   ├── Merged/
│   │   ├── Shaders/                  # effect search path
│   │   │   ├── iMMERSE/             # iMMERSE Ultimate shaders
│   │   │   │   ├── MartysMods/      # shader headers (.fxh)
│   │   │   │   ├── MartysMods_RTGI_DIFFUSE.fx
│   │   │   │   └── ...
│   │   │   ├── PD80_*.fx            # prod80 shaders
│   │   │   └── ...                  # other shader repos
│   │   └── Textures/                 # texture search path
│   │       └── iMMERSE/             # iMMERSE textures
│   ├── reshade-shaders/
│   ├── prod80-shaders/
│   └── ...                          # individual shader repos

Game exe directory (per game):
├── dxgi.dll -> ~/.local/share/reshade/reshade/6.7.3/ReShade64.dll
├── d3dcompiler_47.dll
├── ReShade.ini                       # per-game ReShade config
├── ReShadePreset.ini                 # per-game preset
├── MartysMods_LUTManager.addon64     # iMMERSE addons (per-game)
├── MartysMods_ParallaxDOF.addon64
└── MartysMods_ReGradePlus.addon64
```

## Notes

- Shaders in `Merged/` are shared across all games. Addons must be copied per-game.
- The `reshade-steam-proton.sh` script can be re-run to update ReShade and base shaders.
  iMMERSE Ultimate must be updated manually from new zip releases.
- If ReShade overlay doesn't appear, check `ReShade.log` in the game's exe directory.
- Some games need `opengl32.dll` instead of `dxgi.dll` — check pcgamingwiki.com for the graphics API.
