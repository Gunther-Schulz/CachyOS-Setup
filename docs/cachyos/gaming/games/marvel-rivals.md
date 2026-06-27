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
SteamDeck=1 PROTON_USE_NTSYNC=1 mangohud %command%
```

**Desktop (RTX 5090, 2560×1440 @ 330 Hz)** — same, plus `VKD3D_CONFIG=descriptor_heap`:
```
SteamDeck=1 PROTON_USE_NTSYNC=1 VKD3D_CONFIG=descriptor_heap mangohud %command%
```

| Switch | What it does |
|---|---|
| `SteamDeck=1` | **Skips the NetEase launcher** → boots straight into the game (the reason to use it). camelCase — `SteamDeck`, not `Steamdeck`. *Caveat:* can block first-time login — if login fails, remove it for one launch, then re-add. Some games apply Deck graphics defaults when they see this, but **no reports of that for Marvel Rivals** — here it's just the launcher skip. |
| `PROTON_USE_NTSYNC=1` | Uses the `ntsync` kernel sync primitive (present on CachyOS). |
| `VKD3D_CONFIG=descriptor_heap` | **Desktop / RTX 5090 only.** Mitigates the Blackwell "presentation freezes 3–5 s" bug — *reduces frequency, not a cure*; experimental; benefits the 595 driver branch. Irrelevant on the laptop (Ada 4060). |
| `mangohud` | FPS/frametime overlay + frame limiter (see above). Optionally prefix `gamemoderun` to pin the CPU governor to performance for the session. |

**DLSS — now native, set it in-game.** Marvel Rivals ships **DLSS 4.5 Super Resolution** natively (DLSS 4.5 rollout, Season 7) — pick it in the game's **Settings → Graphics**; no launch flags. The old workaround flags (`PROTON_DLSS_UPGRADE`, `DXVK_NVAPI_…RENDER_PRESET_SELECTION`, `PROTON_DLSS_INDICATOR`) forced the newer DLL / transformer preset *before* native support landed and are now removed — keeping `PROTON_DLSS_UPGRADE` can even swap the game's current 4.5 DLL for an older Proton-bundled one. To check the active version/preset, use the NVIDIA-app overlay or temporarily re-add `PROTON_DLSS_INDICATOR=1`.

**Frame generation — leave it OFF (competitive).** The same update exposes DLSS Frame Generation, plus **Multi Frame Generation** on the desktop (MFG is Blackwell-only — the 5090 gets it; the laptop's 4060 only single FG). Don't enable it for ranked: FG interpolates a synthetic frame *between* two real ones, so it must hold the newer real frame back to blend — adding input latency even with Reflex forced on. Higher *displayed* FPS doesn't help your aim; the added lag hurts it. FG only pays off in GPU-bound single-player where smoothness outranks latency. (On the desktop you're already display-capped at 330 Hz natively at 1440p, so there's nothing to gain there anyway.)

**`PROTON_ENABLE_WAYLAND` — under evaluation.** Native Wayland is being A/B-tested for frametime impact (verdict open). Toggle trick: break the name (e.g. `_ROTON_ENABLE_WAYLAND=1`) to disable it without deleting the line. Judge it over *several* matches on a warm shader cache — single-match comparisons are dominated by shader-compile stutter and scene variance, not the flag. **Known downside:** with it on, the **Steam overlay becomes uninteractable** — you can't even click in it. Turn it OFF whenever you need the overlay (e.g. in-game purchases — see below).

**Desktop 3–5 s freezes** (RTX 5090) are an open NVIDIA **Blackwell driver bug**, not a config issue — reported across 570/575/590 drivers and every compositor. Highest-value mitigation: **toggle VRR/G-SYNC off** (it's a presentation-path bug); `VKD3D_CONFIG=descriptor_heap` reduces frequency. Track [NVIDIA open-gpu-kernel-modules #880](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/880).

**Shader-compile stutter** on first launches is normal for UE5 and smooths as the DXVK cache warms — don't judge performance on a fresh cache.

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
