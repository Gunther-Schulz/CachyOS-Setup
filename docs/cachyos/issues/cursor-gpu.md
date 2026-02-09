# Cursor IDE GPU Acceleration Issues

Cursor IDE can experience severe slowdowns during long chat sessions due to GPU acceleration failures, causing fallback to software rendering.

**Symptoms:** Progressive slowdown during long conversations; high CPU from gpu-process (20%+); system unresponsive during UI; fixed by restarting Cursor.

**Root cause:** GPU acceleration failure during extended sessions; fallback to SwiftShader (`--use-angle=swiftshader-webgl`); complex chat DOM slow on CPU; WebGL context exhaustion or Wayland/Electron compatibility.

**Diagnosis:**
```bash
# Check if Cursor is using software rendering
ps aux | grep cursor | grep "swiftshader-webgl"

# Monitor GPU process CPU usage
ps aux --sort=-%cpu | grep "gpu-process" | head -1

# Check for multiple instances
pgrep cursor | wc -l
```

**Solutions:**

1. **Force stable GPU rendering:** Launch with flags to reduce fallback to software rendering:
   ```bash
   cursor --disable-gpu-sandbox --enable-gpu-rasterization
   ```

2. **Monitor during slowdown:** `watch -n 1 "ps aux --sort=-%cpu | grep 'gpu-process' | head -1"`

3. **Restart when slowdown begins:** `pkill cursor && cursor`

**Note:** Related to Wayland + Electron + GPU acceleration; manifests as gpu-process high CPU from software rendering fallback.
