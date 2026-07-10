# Noise suppression (mic or far-end) — DeepFilterNet3 on PipeWire

Real-time RNN noise suppression, either direction:
- **Mic** — clean your own voice before it goes out (classic NoiseTorch use).
- **Far-end** — clean the *other* person's background noise before it hits your speakers (e.g. a noisy Google Meet participant).

## NoiseTorch is dead on PipeWire ≥1.6 — don't use it

**Symptom:** NoiseTorch GUI opens, "load" silently does nothing, no error in the UI.

**Root cause (entirely PipeWire-side):** NoiseTorch extracts its RNNoise plugin to a random `/tmp/librnnoise-*.so` and asks the server to load `module-ladspa-sink` at that **absolute path**. PipeWire (≥1.6) reimplements `module-ladspa-sink` on its `filter-graph` engine, whose LADSPA loader **only searches `LADSPA_PATH`** (`/usr/lib64/ladspa:/usr/lib/ladspa:/usr/lib`) by basename — it ignores absolute `/tmp` paths. Plugin never found → `ENOENT` → silent fail. NoiseTorch (last release 2022) can't be told to do otherwise.

**Diagnosing any "silent load" audio failure** — the app throws stderr away; the real error is server-side:
```sh
journalctl --user -b | grep -i noise        # look for: failed to load plugin '/tmp/...' No such file or directory
noisetorch -i -log                           # NoiseTorch's own debug view
```

## DeepFilterNet3 — the replacement

RNNoise (what NoiseTorch **and** EasyEffects "Noise Reduction" both use) is a tiny 2017 model. **DeepFilterNet3** is a modern deep-filtering model — far stronger on non-stationary noise (typing, babble) — and its LADSPA plugin installs into `/usr/lib/ladspa/`, so PipeWire resolves it by basename (no `/tmp` problem).

### Install
```sh
paru -S libdeep_filter_ladspa-bin
```
Prebuilt (no Rust compile). Provides `/usr/lib/ladspa/libdeep_filter_ladspa.so`, DFN3 low-latency model **embedded** (no external model file). Labels: `deep_filter_mono`, `deep_filter_stereo`.

### Virtual sink (far-end / per-stream)
Creates a filtered sink; route only chosen streams through it. User drop-in, no sudo —
`~/.config/pipewire/pipewire.conf.d/99-deepfilter-sink.conf`:

```
context.modules = [
    {   name = libpipewire-module-filter-chain
        flags = [ nofail ]
        args = {
            node.description = "DeepFilter Noise Suppression"
            media.name       = "DeepFilter Noise Suppression"
            filter.graph = {
                nodes = [
                    {   type    = ladspa
                        name    = deepfilter
                        plugin  = libdeep_filter_ladspa
                        label   = deep_filter_stereo
                        control = {
                            "Attenuation Limit (dB)" = 100
                            "Post Filter Beta"       = 0.05
                        }
                    }
                ]
            }
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props  = { node.name = "effect_input.deepfilter"  media.class = Audio/Sink }
            playback.props = { node.name = "effect_output.deepfilter" node.passive = true }
        }
    }
]
```
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
