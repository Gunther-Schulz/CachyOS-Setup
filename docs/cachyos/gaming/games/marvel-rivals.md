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

Both machines run Marvel Rivals (UE5) under **proton-cachyos** (assume the latest) — set in Steam → game **Properties → Launch Options**. **The two machines need different strings** — `VKD3D_CONFIG=descriptor_heap` is safe *only* on Blackwell + the 595 driver (see the table):

**Laptop (FA607PV — RTX 4060 Ada, nvidia-open 610):**
```
SteamDeck=1 DXVK_NVAPI_VKREFLEX=1 PROTON_ENABLE_WAYLAND=1 mangohud %command%
```

**Desktop (RTX 5090 Blackwell, 595 driver, 2560×1440 @ 330 Hz):**
```
SteamDeck=1 DXVK_NVAPI_VKREFLEX=1 VKD3D_CONFIG=descriptor_heap mangohud %command%
```

| Switch | What it does |
|---|---|
| `SteamDeck=1` | **Skips the NetEase launcher** → boots straight into the game (the reason to use it). camelCase — `SteamDeck`, not `Steamdeck`. *Caveat:* can block first-time login — if login fails, remove it for one launch, then re-add. Some games apply Deck graphics defaults when they see this, but **no reports of that for Marvel Rivals** — here it's just the launcher skip. |
| `DXVK_NVAPI_VKREFLEX=1` | **Makes NVIDIA Reflex actually function** (NVIDIA-only) — and you must **also turn Reflex on in-game**; the two are required together. Without this, dxvk-nvapi's Vulkan Reflex layer stays *disabled by default* and the game's Reflex calls get **fake-success stubs**: the in-game toggle *looks* active but reduces **zero** latency. The old cachy spelling `PROTON_VKREFLEX=1` was removed — this upstream name is the current one. |
| `PROTON_ENABLE_WAYLAND=1` | Native Wayland present path — a frametime win, leaner than XWayland (see note below). **Downside:** breaks the Steam overlay (uninteractable) — disable it for in-game purchases. If you get NVIDIA sync/present glitches, this is the first flag to drop. |
| `VKD3D_CONFIG=descriptor_heap` | **Desktop ONLY (Blackwell + 595 driver).** Enables the experimental `VK_EXT_descriptor_heap` path, which on the 595 driver *fixes* the **Xid 109 "CTX SWITCH TIMEOUT"** hard crash and trims the Blackwell freeze frequency. ⚠️ **Don't use on the laptop (Ada 4060)** — it was strongly implicated in Xid 109 GPU hangs + graphics corruption on the old **580** driver (2026-07-07: appeared while set, stopped when removed — *correlation, not proof*). The laptop is now on **nvidia-open 610**, where the interaction is untested, so keep it off by default; its benefit was marginal/illusory anyway. `PROTON_VKD3D_HEAP=1` is the removed old spelling. |
| `mangohud` | FPS/frametime overlay + frame limiter (see above). Optionally prefix `gamemoderun` to pin the CPU governor to performance for the session. |

**NTSync is automatic — don't set it.** `ntsync` is default-on in current proton-cachyos and the `PROTON_USE_NTSYNC` flag was removed (dead no-op). `PROTON_NO_NTSYNC=1` disables it only if a title misbehaves.

**Don't add `VKD3D_CONFIG=upload_hvv`.** It puts the D3D12 UPLOAD heap in ReBAR/host-visible VRAM, but vkd3d-proton already handles this by heuristic: **> 8 GB cards get it by default; ≤ 8 GB cards are deliberately excluded** because they hit the VRAM ceiling and stutter. So the **5090 already has it** (no flag needed), and on the **8 GB laptop 4060 forcing it re-introduces the exact VRAM-exhaustion stutter** the heuristic avoids — worse with the GNOME compositor now sharing that 8 GB ([why](../../laptop/amdgpu-gfx-ring-timeout.md)). Forcing it globally also overrides vkd3d's per-game `no_upload_hvv` safety profiles. Leave it to the heuristic.

**Recovery if a bad flag already corrupted the shader cache** *(working theory, 2026-07-07 — not proven).* Assumed mechanism: an **Xid 109 hang mid-shader-compile** leaves a corrupt/partial binary in the NVIDIA driver cache under a valid hash, so every later launch reuses it → graphics corruption that **survives** both removing the offending flag *and* clearing the game/Steam caches. Removing `descriptor_heap` alone is **not enough** once this has happened — you must wipe the driver cache too (game + the Steam-launched game closed):
```sh
rm -rf ~/.cache/nvidia                                    # global driver shader cache — everything recompiles once
rm -rf ~/.local/share/Steam/steamapps/shadercache/2767030
# then set IsGlobalPSOCompiled=False in MachinePSOConfig.ini for a clean up-front recompile
```
After a full wipe + clean recompile on the driver-native path (descriptor_heap out of the launch options), the corruption cleared completely — and the game ran *smoother than before*, since the rebuilt cache also shed months of stale cruft. Honest caveat: the descriptor_heap → Xid 109 → cache-corruption chain fits the timeline and the fix worked, but it wasn't reproduced on purpose to prove causation.

**DLSS — now native, set it in-game.** Marvel Rivals ships **DLSS 4.5 Super Resolution** natively (DLSS 4.5 rollout, Season 7) — pick it in the game's **Settings → Graphics**; no launch flags. The old workaround flags (`PROTON_DLSS_UPGRADE`, `DXVK_NVAPI_…RENDER_PRESET_SELECTION`, `PROTON_DLSS_INDICATOR`) forced the newer DLL / transformer preset *before* native support landed and are now removed — keeping `PROTON_DLSS_UPGRADE` can even swap the game's current 4.5 DLL for an older Proton-bundled one. To check the active version/preset, use the NVIDIA-app overlay or temporarily re-add `PROTON_DLSS_INDICATOR=1`.

**Frame generation — leave it OFF (competitive).** The same update exposes DLSS Frame Generation, plus **Multi Frame Generation** on the desktop (MFG is Blackwell-only — the 5090 gets it; the laptop's 4060 only single FG). Don't enable it for ranked: FG interpolates a synthetic frame *between* two real ones, so it must hold the newer real frame back to blend — adding input latency even with Reflex forced on. Higher *displayed* FPS doesn't help your aim; the added lag hurts it. FG only pays off in GPU-bound single-player where smoothness outranks latency. (On the desktop you're already display-capped at 330 Hz natively at 1440p, so there's nothing to gain there anyway.)

**`PROTON_ENABLE_WAYLAND` — on (laptop).** Native Wayland's present path is leaner than XWayland (no extra copy), amplified on the laptop by the GNOME compositor now running on the *same* dGPU as the game ([why](../../laptop/amdgpu-gfx-ring-timeout.md)). (The desktop can use it too — the Blackwell freeze is unaffected either way.) Judge frametime over *several* matches on a warm shader cache — single-match comparisons are dominated by shader-compile stutter and scene variance, not the flag. **Known downside:** with it on, the **Steam overlay becomes uninteractable** — you can't even click in it. Toggle trick: break the name (e.g. `_ROTON_ENABLE_WAYLAND=1`) to disable it without deleting the line — do this whenever you need the overlay (e.g. in-game purchases — see below).

**Desktop 3–5 s freezes** (RTX 5090) are an open NVIDIA **Blackwell driver bug**, not a config issue — reported across 570/575/590 drivers and every compositor. It lives at the **session + driver** level, so the game's Proton backend doesn't move it: running under XWayland instead of `PROTON_ENABLE_WAYLAND` **did not help**, and `VKD3D_CONFIG=descriptor_heap` only **reduces the frequency — not a cure**. Highest-value mitigation: **toggle VRR/G-SYNC off** (it's a presentation-path bug). Track [NVIDIA open-gpu-kernel-modules #880](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/880).

**Shader-compile stutter — and why it recurs after every driver/Proton update.** First-launch stutter is normal UE5 and smooths as the cache warms. But it *comes back* mid-match — often on a first-seen effect like an ult — after any **NVIDIA driver or proton-cachyos update**, because both invalidate the shader cache: on Linux the pipeline is built in two stages (vkd3d-proton does D3D12→SPIR-V, then the NVIDIA driver compiles SPIR-V→GPU code), and a change in *either* stage misses the cache. Familiar shaders then recompile on-demand, in-match. So you must watch **both** the driver and Proton, not just the driver.

**The Linux trap:** Marvel *has* an up-front "compiling shaders, don't start a match yet" screen, gated in `…/Marvel/Saved/Config/Windows/MachinePSOConfig.ini` by `IsGlobalPSOCompiled` + `GPUInternalDriverVersion`. On Windows that version moves with each driver and re-triggers the screen. Under Proton, **vkd3d reports a static `GPUInternalDriverVersion=35.0.99.9999`** that never changes, so the game never notices a driver/Proton change and *skips* the screen — silently recompiling in-match instead. Deleting the shader caches does **not** trigger it either: the screen is gated on that flag, not on cache presence.

**Force the up-front screen** (with the game **closed** — it rewrites this file on exit): set `IsGlobalPSOCompiled=False` **and** `IsAdditionalPSOCompiled=False` in that file, relaunch → the compile screen runs. (Deleting `Marvel/Saved/Marvel_PCD3D_SM6.upipelinecache` + `CollectedPSOs` + Steam's `steamapps/shadercache/2767030` is a heavier hammer, but the flag is the actual trigger.)

**Automate it — a pacman hook** (a launch-options wrapper *doesn't* work: it runs inside Steam's runtime, whose `LD_LIBRARY_PATH` breaks host binaries like `pacman`, so its version check comes up empty and can't tell Proton changed — verified). A hook runs in pacman's *own* context on each driver/Proton upgrade and flips the flag there. Deploy [`gaming/mr-pso-recompile.hook`](https://github.com/Gunther-Schulz/dotfiles) to `/etc/pacman.d/hooks/`:
```
sudo cp ~/dev/Gunther-Schulz/dotfiles/gaming/mr-pso-recompile.hook /etc/pacman.d/hooks/
```
It triggers on any `nvidia-*utils`/`nvidia-*dkms` and `proton-cachyos*` upgrade — **glob targets**, so a driver-branch change (580→590, or a switch to `nvidia-open`) keeps working instead of silently no-op'ing — and runs (as your user, to preserve file ownership) a `sed` that flips `IsGlobalPSOCompiled=True`→`False` in `MachinePSOConfig.ini` → the next launch shows the compile screen. Keep the launch options plain (no wrapper).

**Steam's own pre-caching doesn't help on NVIDIA — leave it off.** On the proprietary NVIDIA driver, Steam's Fossilize pre-caching (*Settings → Downloads → Shader Pre-Caching*) *runs* — downloads `.foz`, does the "Processing Vulkan shaders" pass — but the driver **never uses the cache it produces** (reported "completely useless" on NVIDIA; the pre-compiled shaders aren't picked up, so you stutter in-game anyway). Net cost: GBs of disk, background CPU, and the launch delay, for **zero** gain (it's why the MR Fossilize cache sat frozen since Oct 2025). What actually prevents the stutter here is the **NVIDIA driver's own cache** (`~/.cache/nvidia`) + Marvel's PSO precompile (above). So turn **off** *Allow background processing of Vulkan shaders* (optionally *Enable Shader Pre-Caching* entirely) — on **both** machines, since both are NVIDIA. **AMD/RADV is the opposite** (Mesa *does* consume the Fossilize cache), which is where the generic "enable it" advice comes from — it just doesn't transfer to NVIDIA.

## Buying Lattice (premium currency) on Linux

Lattice is the paid currency (skins / Battle Pass; converts 1:1 to Units). It's an **in-game microtransaction** billed through Steam — no Steam store page exists for it, so it must be bought from inside the game via the **Steam overlay**. On Linux that path has three separate traps; this is the procedure that actually works (validated 2026-06-25, laptop, GNOME Wayland):

**1. Enable the Steam overlay first.** Settings → In Game → **Enable the Steam Overlay while in-game** (the *per-game* checkbox stays greyed until this *global* one is on). Confirm `Shift+Tab` opens it in-game. Multiple Steam accounts? The overlay setting, launch options, Wallet balance, and saved billing address are **all per-account** — do everything on the account your Rivals progress is on.

**2. Pay from Steam Wallet, not PayPal-in-the-overlay.** The overlay's embedded browser (CEF) **crashes on PayPal's security-check page** — you enter your PayPal login, then get a grey box with a sad-face icon at the verification step. Avoid that path entirely: **pre-load Steam Wallet** first (Steam client → your name → *Account details* → *Add funds to your Steam Wallet*, or store.steampowered.com in a real browser — PayPal's security check renders fine in a full browser). Then in-game, buy Lattice and choose **Steam Wallet** → no external payment page, no crash. (Minimum top-up ≈ €5/$5; smallest Lattice pack ≈ $0.99. A Wallet top-up does *not* ask for a billing address — only the Lattice purchase does, see next.)

**3. The billing-address prompt + the overlay keyboard bug.** The Lattice microtransaction asks for a **billing address** (tax/VAT) and collects it in the overlay — where, on **Wayland, the Steam overlay won't accept keyboard input**: you can click a field and it highlights, but typing does nothing (a long-standing Valve bug, [steam-for-linux #9694](https://github.com/ValveSoftware/steam-for-linux/issues/9694)). What works:

- ✅ Type each address value in a normal text editor (keyboard works there) → **Ctrl+C** → in the overlay field **right-click → Paste**.
- ❌ Typing directly, middle-click / primary-selection paste, and the Big-Picture on-screen keyboard all fail or are unusably slow here.
- Bulletproof alternative: enter the address **once under a GNOME on Xorg session** (the overlay keyboard works under Xorg), then switch back to Wayland.

Steam **saves the address**, so this is one-time — future Lattice buys are just *Wallet → confirm*, mouse only.

**Don't have `PROTON_ENABLE_WAYLAND` enabled for purchases** — native Wayland makes the overlay completely uninteractable (can't even click), which is worse than the keyboard bug. Disable it (break the name as above) before buying.
