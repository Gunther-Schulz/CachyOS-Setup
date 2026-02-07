# PipeWire and Helvum

**Install:** `sudo pacman -S pipewire-jack helvum`.

**Low latency:**
```bash
pw-metadata -n settings 0 clock.force-rate 48000
pw-metadata -n settings 0 clock.force-quantum 128
```

**Helvum:** Drag source → destination for connections; both L/R for stereo. Redraw same connection to remove. Use pavucontrol for levels, pw-top to monitor.
