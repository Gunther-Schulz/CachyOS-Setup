# Cursor IDE GPU Acceleration

**Symptoms:** Progressive slowdown in long chat; high CPU from gpu-process (20%+); unresponsive UI; fixed by restarting Cursor.

**Cause:** GPU acceleration failure → fallback to SwiftShader (`--use-angle=swiftshader-webgl`). Wayland/Electron/WebGL compatibility.

**Diagnosis:** `ps aux | grep cursor | grep "swiftshader-webgl"`; `ps aux --sort=-%cpu | grep "gpu-process"`; `pgrep cursor | wc -l`.

**Mitigations:**
1. Launch with: `cursor --disable-gpu-sandbox --enable-gpu-rasterization`.
2. Monitor: `watch -n 1 "ps aux --sort=-%cpu | grep 'gpu-process' | head -1"`.
3. Restart when slow: `pkill cursor && cursor`.
