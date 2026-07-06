# Discord

**Machine:** Laptop (FA607PV).

## Hangs on a blank window → disable hardware acceleration

Since GNOME composites on the **NVIDIA dGPU** ([laptop/amdgpu-gfx-ring-timeout.md](../laptop/amdgpu-gfx-ring-timeout.md)), Discord's older **Electron 37** keeps rendering on the **AMD iGPU** and its cross-GPU dmabuf fails to import into the compositor — so the window hangs blank:

```
wayland_error: failed to import supplied dmabufs: Could not bind the given EGLImage to a CoglTexture2D
'GPU' process exited with 'abnormal-exit'
```

(Newer Electron apps like Claude Desktop follow the compositor to the dGPU and don't hit this.)

**Fix — turn off GPU acceleration** (a chat app doesn't need it). With **Discord fully closed** (else it rewrites the file on exit), in `~/.config/discord/settings.json`:

```json
"enableHardwareAcceleration": false
```

Or toggle it in **Settings → Advanced → Hardware Acceleration** once the window is reachable. Discord then CPU-renders (SHM buffers the compositor imports fine) — no hang, and no iGPU-crash risk either. Screenshare is unaffected (PipeWire portal + OpenH264, already enabled).

**Env vars can't fix this.** `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `__EGL_VENDOR_LIBRARY_FILENAMES`, and the PRIME-offload vars **don't** redirect Chromium's GPU pick (they steer Mesa/GLX apps only) — tested. Full reasoning: [amdgpu-gfx-ring-timeout.md → stale-Electron apps](../laptop/amdgpu-gfx-ring-timeout.md#stale-electron-apps-discord-hang-on-the-dgpu).

**Laptop-only** — the desktop hides its AMD APU, so Discord runs entirely on the RTX 5090 and needs no change.
