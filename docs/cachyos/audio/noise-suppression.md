# Noise suppression (mic or far-end) — DeepFilterNet3 on PipeWire

Real-time RNN noise suppression, either direction:
- **Mic** — clean your own voice before it goes out.
- **Far-end** — clean the *other* person's background noise before it hits your speakers (e.g. a noisy Google Meet participant).

## DeepFilterNet3

The older RNNoise model (2017) is weak on non-stationary noise. **DeepFilterNet3** is a modern deep-filtering model — far stronger on typing/babble — and its LADSPA plugin installs into `/usr/lib/ladspa/`, so PipeWire resolves it by basename.

### Install
```sh
paru -S libdeep_filter_ladspa-bin
```
Prebuilt (no Rust compile). Provides `/usr/lib/ladspa/libdeep_filter_ladspa.so`, DFN3 low-latency model **embedded** (no external model file). Labels: `deep_filter_mono`, `deep_filter_stereo`.

### Virtual sink (far-end / per-stream)
Creates a filtered sink; route only chosen streams through it. The config is a user drop-in at `~/.config/pipewire/pipewire.conf.d/99-deepfilter-sink.conf` — **tracked in dotfiles** (`pipewire/99-deepfilter-sink.conf`, deployed by `install.sh`). It defines a `libpipewire-module-filter-chain` sink named **"DeepFilter Noise Suppression"** (the `deep_filter_stereo` LADSPA plugin; input node `effect_input.deepfilter`). Tune it via the control table below.
Apply + verify:
```sh
systemctl --user restart pipewire
pactl list short sinks | grep -i deepfilter        # -> effect_input.deepfilter ... RUNNING/SUSPENDED
```
For a **mic source** instead (clean your own voice), use `media.class = Audio/Source` with `label = deep_filter_mono` — see upstream `ladspa/filter-chain-configs/`.

### Enable/disable = route the stream (no global switch)
The sink is idle (≈0 CPU) until a stream is routed to it.
- **GUI:** `pavucontrol` → Playback → set the call/Chrome stream's output to **"DeepFilter Noise Suppression"**. Set back to your speakers to disable.
- **CLI:** `pactl move-sink-input <ID> effect_input.deepfilter` (on) / `pactl move-sink-input <ID> @DEFAULT_SINK@` (off). Find `<ID>` with `pactl list short sink-inputs`.
- **Remove entirely:** `mv 99-deepfilter-sink.conf{,.disabled}` + `systemctl --user restart pipewire`.

**Per-stream, not per-app** (EasyEffects include/exclude): a browser is one app carrying the call *and* other tabs, so app-level scoping can't isolate the call — routing a single stream can.

### Tuning (control ranges verified against `ladspa/src/lib.rs`)
Edit the `control` block, then `systemctl --user restart pipewire`.

| Control | Default | Range | Effect |
|---|---|---|---|
| `Attenuation Limit (dB)` | 100 | 0–100 | Suppression cap. **100 = max** (no limit); 18–24 medium; 6–12 light/natural. |
| `Post Filter Beta` | 0 (off) | 0–0.05 | Residual-noise aggressiveness. **0.05 = strongest**; back to 0.02 if voice sounds robotic. |
| `Max DF processing threshold (dB)` | 20 | −15–35 | Raise toward 35 → deep-filter stage runs on more frames (more thorough, more CPU). |
| `Max ERB processing threshold (dB)` | 30 | −15–35 | As above, stage 1. |
| `Min processing threshold (dB)` | −15 | −15–35 | Lower → acts on quieter noise. |
| `Min Processing Buffer (frames)` | 0 | 0–10 | Raise to 3–5 **only** if choppy (journal: "Processing too slow"). |

### Far-end ceiling
Filtering the *other* side of a call runs on audio already degraded by the Opus codec + the sender's own noise suppression — an inherent ceiling, far less headroom than cleaning your own raw mic. Past a point, cranking Post Filter Beta / thresholds just adds artifacts. The biggest win for a noisy caller is **them** enabling suppression on their end.
