# Marvel Rivals — Audio Fix

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
