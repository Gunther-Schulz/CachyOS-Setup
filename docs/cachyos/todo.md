# Todo

- **Desktop:** board RMA option — seller agreed weeks back; unsure if still honored. Confirm the window is still open (free, one message) **before** deciding. Decide with two facts in hand: (a) USB-C port test result, (b) memtest on new RAM — dead port or memtest errors → take RMA; both clean → keep + monitor, RMA only if evidence appears. Background: [hardware/ram-surge-damage.md](hardware/ram-surge-damage.md).
- **Desktop:** RAM/board surge check — background: [hardware/ram-surge-damage.md](hardware/ram-surge-damage.md).
  1. Memtest86+ overnight (≥4 full passes) with the known-good RAM (`sudo pacman -S memtest86+-efi`, then pick it in the boot menu). Short test already ran clean; long run outstanding.
  2. Repeat right after the new RAM is installed — within the 14-day withdrawal window, so a DOA module is trivial to return.
  3. ✅ First reading 2026-08-03: **0 MCE/EDAC events over 7 days** — clean. `rasdaemon` is **not installed** (step 4 below), so this journal grep is currently the only ledger and it does not survive reboots. Until several clean weeks have passed, check weekly:
     ```sh
     journalctl -k --since "-7 days" | grep -iE "mce|edac|machine check|corrected error"
     ```
  Both memtests clean + several quiet weeks → board cleared, remove this item and mark the doc closed. Any memtest error → suspect the board, not the RAM.
  4. Wider board checkout (surge went through data lines twice — test beyond the memory path), all quick:
     - every USB port enumerates with a **disposable** stick (rear USB-C is the untested suspect — see the doc; data-only, nothing self-powered). **The amp's port is unknown** (not remembered), so no port is pre-cleared — sweep ALL of them, front + rear, and note per-port results in the doc as you go;
     - deeper per-port electrical check with a **USB tester dongle** (~€10–20 on Amazon): search "FNIRSI FNB48" / "FNB58" or "TC66C" (USB-C, shows VBUS voltage/current live) or a simple "UM25C" (USB-A). What it proves: VBUS sits at 5.0 V ±5% idle, doesn't sag/spike when a stick enumerates — a port with surge-damaged power delivery shows off-spec VBUS before it shows data failures. What it can't prove: data-lane signal integrity at 10 Gbps (only a real high-speed transfer tests that — copy a few GB to a fast stick and check `dmesg` for resets/downshifts, `lsusb -t` for the negotiated speed). €15 well spent for the RMA-evidence angle: an off-spec VBUS reading is *demonstrable* defect documentation;
     - PCIe links at full width/speed: `sudo lspci -vv | grep -E "LnkCap|LnkSta"` — degraded lanes (e.g. x16 card at x8, or Gen5 at Gen3) are a classic silent surge symptom. ✅ **GPU already clear (2026-08-03):** `nvidia-smi` reports the 5090 at **Gen 5 × 16, equal to its max** — the highest-value lane in the machine is not degraded. Remaining: the NVMe and chipset links via `lspci`;
     - ✅ NVMe health — **all three clean, 2026-08-03.** Available Spare 100% / Media and Data Integrity Errors 0 / Critical Warning 0x00 on every drive; wear `nvme0` 3%, `nvme1` 1%, `nvme2` 0%; temps 42–44 °C against 85–88 °C thresholds. Error Information Log entries (5 / 3 / 0) are a lifetime counter, not a fault — no media errors beside them. Nothing here supports drive-side surge damage. **One number worth watching, not a drive fault:** `nvme0` reports **319 Unsafe Shutdowns** over 4 868 power-on hours (~1.7 y) — roughly one per other boot. It is a **lifetime** counter that never falls, so it aggregates every hard-cycle event since the drive was new — including the period when the sleep and IOMMU bugs were open. Whether those are still occurring is **unverified** (fixes are documented as applied; not re-checked). Not evidence about the drive or the surge either way. The useful reading is the **rate**, not the total: baseline is **319 at 4 868 power-on hours, 2026-08-03** — re-read later and compare. Still climbing = something is hard-cycling the machine;
     - NVMe firmware — see the standalone item below (not surge-specific; do it as part of this sweep anyway);
     - audio codec + LAN: play something over each output once, `ethtool <if>` link at expected speed;
     - start `rasdaemon` (`sudo pacman -S rasdaemon && sudo systemctl enable --now rasdaemon`) — persistent MCE/EDAC ledger (`ras-mc-ctl --errors`), stronger than the weekly journal grep because it survives reboots and catches corrected errors that never hit the journal.
- **Desktop: set RAM to its rated speed (EXPO) in BIOS — not yet done, and sequencing matters.** New RAM installed after the surge; with no EXPO profile selected the board runs it at the JEDEC default (typically 4800 MT/s), well under the kit's rating. Check what it's actually running now: `sudo dmidecode -t memory | grep -E "Speed|Configured Memory Speed"` (`Configured` is the live speed, `Speed` is the SPD-rated one — if they differ, EXPO is off).
  **Order (operator decision 2026-08-03): EXPO FIRST, then fall back only if it fails.** A clean memtest *at* EXPO is the stronger result — it exercises the memory controller harder, so passing clears the RAM and the board in one run. The fallback restores attribution if needed. Full branch in the BIOS checklist below.
- **Desktop:** 9950X3D efficiency tuning — 105 W ECO mode + Curve Optimizer undervolt (~−15…−25 per core, weakest cores less). **Sequencing: only AFTER the surge-check item above is fully cleared** — CO instability and latent board damage look identical (random reboots, corrected MCEs); tuning before the board is cleared destroys the diagnostic signal.
  CO stability testing on Linux (CoreCycler/OCCT are Windows-first; equivalents):
  1. Single-core cycling (the failure mode CO creates — solo boost at low current): `mprime` (AUR `mprime-bin`) pinned to one core at a time via `taskset -c N`, SSE torture first (highest boost = most fragile), then AVX2; cycle all 32 threads, ~10 min/core overnight, script the loop. This *is* CoreCycler minus the PowerShell.
  2. `y-cruncher` (native Linux tarball) component stress tests — different math paths, catches what mprime misses.
  3. Idle soak a full day — CO fails at *idle/light load*, not just under stress. Watch `ras-mc-ctl --errors` / `journalctl -k | grep -iE "mce|machine check"`: corrected Cache Hierarchy errors = back off 5 on that core even without a crash (the Linux equivalent of WHEA 18/19 warnings).
  4. Any single failing core: relax only that core's offset (+5), re-run; then a week of normal use as final judge.
  Payoff at 105 W: ~95% multicore, ~half the load power/heat; gaming and single-thread unaffected (X3D loads run 60–90 W anyway).
  **Before/after benchmark protocol — automated: [`tools/cpu-bench.sh`](../../tools/cpu-bench.sh).**
  ```sh
  sudo pacman -S stress-ng turbostat            # prerequisites
  sudo ./tools/cpu-bench.sh stock               # BEFORE any BIOS change — unrepeatable later
  sudo ./tools/cpu-bench.sh eco                 # after ECO alone
  sudo ./tools/cpu-bench.sh eco-co              # after ECO + Curve Optimizer
  ```
  Runs the battery below 3× each and reports medians (single runs are noise), with `turbostat` logging power/clocks/temps *during* the load. Writes to `~/bench/<label>/`: raw output, turbostat logs, `summary.txt`, and **`conditions.txt`** — kernel, governor, EPP, power mode, RAM speed, loadavg. That last file is the point: `diff ~/bench/stock/conditions.txt ~/bench/eco/conditions.txt` catches a power-mode or RAM-speed change between runs, which is the failure that silently invalidates the whole comparison. Warns and pauses if loadavg > 1.5; settles 15 s between runs.
  ✅ **RESULTS: [hardware/9950x3d-eco-expo.md](hardware/9950x3d-eco-expo.md).** Headline — ECO is binding (142.0 W pinned, exactly the 105 W tier's PPT), multicore **−12.4 %** for **−28.8 %** power = **+23 % perf/watt**, single-thread untouched.

  **Script defect log — three found, all by running it rather than reading it:**
  1. **`PkgWatt` → `n/a`.** `turbostat --out` writes an elapsed-time line (`60.014170 sec`) *before* the column header; the parser only looked at line 1. Fixed — the header is found wherever it sits. Re-parsing the **saved** stock logs recovered the numbers, so the unrepeatable baseline survived.
  2. **`CoreTmp` produced no column** in the `-S` summary row. Changed to `PkgTmp`.
  3. **`PkgTmp` produced no column either** (2026-08-04) — the `-S` header came back as literally `Busy% Bzy_MHz PkgWatt`. **turbostat exposes no temperature on this AMD platform**, so temperature was moved off it entirely and onto **`k10temp` via sysfs**, sampled every 2 s during the load. Strictly better: it gives **Tctl** (what the board's fan curve follows) *and* per-CCD temps, and on a 9950X3D the two CCDs differ sharply — measured 2026-08-04 at low load, **Tccd1 44.8 °C vs Tccd2 70.0 °C**. Verified producing real numbers before being relied on.

  The pattern is worth keeping: each defect reported plausibly and measured nothing, and only executing the tool exposed it. `stock` and `eco-expo` therefore have **no temperature data**; the first run to carry it will be the post-CO one.

  **Stock baseline — 2026-08-03 23:06, 32 threads, `powersave`/`balance_performance`/`amd-pstate-epp`, GNOME power mode `balanced`, RAM 4800 MT/s (pre-EXPO), 3 × 60 s:**

  | Test | median bogo-ops/s | median PkgWatt | median Bzy_MHz |
  |---|---|---|---|
  | multicore (`--matrix 0`) | **116 500** | **199.4 W** | **4 952** |
  | single-thread (`--cpu 1 --cpu-method fft`) | **5 047** | **59.6 W** | **5 368** |

  Watts/MHz recovered from `~/bench/stock/*-turbostat.txt` after the parser fix; `PkgTmp` is absent for stock because that run did not request the column. The stock `summary.txt` on disk still shows `n/a` for watts — the table above supersedes it.
  The underlying battery, if running by hand:
  - Multicore throughput: `mprime` bench mode or `stress-ng --matrix 0 --metrics-brief -t 60`; plus a real workload you care about — a kernel/large-project compile timed with `time` (best of 3, warm cache) is the honest one.
  - Single-thread: `geekbench6` (AUR) or `stress-ng --cpu 1 --cpu-method fft --metrics-brief -t 60` — expect ~0 change; this is the "did CO/ECO hurt boost" check.
  - Sustained clocks + power + temps DURING the multicore run, logged not eyeballed: `sudo turbostat --interval 5 --quiet -S --show PkgWatt,PkgTmp,Busy%,Bzy_MHz` teed to a file (**`PkgTmp`, not `CoreTmp`** — the latter yields no column in the `-S` summary row and reads as a silent `n/a`) for the run's duration. The turbostat log is the real payoff evidence — perf-per-watt before vs after.
  - Gaming proxy (X3D's job): one repeatable in-game benchmark or `glmark2`/a capped-FPS scene with `mangohud` logging (frametime p1/p99, not just avg FPS) — same scene, same settings, both runs.
  - Rules: same kernel + governor + fan profile both runs; note ambient temp; 3 runs each, report median; do the AFTER run only once CO has passed the stability regimen (an unstable-but-fast result is noise).
- **Desktop:** consider undervolting the RTX 5090 — same philosophy as the CPU item: the last ~100 W of its 575 W budget buys a few percent. Linux reality check first: nvidia-smi/NVML expose **power-limit** and **clock-offset** controls, but true V/F-curve undervolting (the MSI-Afterburner method) is not directly exposed on Linux — the standard technique is the proxy: `nvidia-smi -pl <W>` (e.g. 450–480 W, ~80–85%) **plus** a positive core-clock offset via `nvidia-settings`/nvml (`+150…+300 MHz`), which shifts the effective V/F point the same direction. On the 5090, community results cluster around ~90% performance at ~70–75% power. Test protocol mirrors the CPU one: baseline benchmark first (same mangohud frametime logging + a sustained load like a long render/`gravitymark`), turbostat-equivalent = `nvidia-smi dmon -s pucvmet -o DT -f gpu-log.csv` (**corrected 2026-08-04, verified live** — this doc previously said `-s pucT`, which is simply invalid syntax: there is no capital-`T` metric, the valid `-s` letters are `p u c v m e t n` and lowercase `t` means PCIe *throughput*, not temperature. It failed with "Failed to find any metric to display" and was wrongly recorded here as a card/driver limitation. `-o DT` is what adds the Date/Time columns. The `mtemp` column reads `-` — use `nvidia-gpu-sensors` for memory temp, see the item below); stability = hours of a demanding game/render without artifacts or driver resets (`journalctl -b | grep -i xid` — any Xid error = back off the offset). Sequencing: independent of the board-clearance chain (GPU wasn't in the surge path), but do it BEFORE fan curves for the same reason as the CPU — curves get tuned once against the final heat output of both chips. (curves tuned against pre-ECO heat output would all be wrong afterward; tune once against the final thermal envelope). Assets already in repo: `fan-control/` (coolercontrol scripts + channel labels). Approach: with 105 W ECO + CO settled, log temps under (a) idle, (b) gaming-typical 60–90 W, (c) all-core 105 W; then set curves for silence at (a)/(b) and acceptable acoustics at (c) — the X3D cache die tolerates up to ~89 °C Tjmax, so target quiet-first, not cool-first.
- **Desktop — fans surge under LIGHT load, not heavy. Keep ECO Mode; the fix is Curve Optimizer + fan hysteresis.**

  **Measured on this machine 2026-08-04 — Tctl peaks at PARTIAL load, not full load.** Thread-count sweep, `--cpu N --cpu-method fft`, 35 s each from a 25 s-cooled start:

  | Threads | **Tctl peak** | Tccd1 | Tccd2 |
  |---|---|---|---|
  | idle | 51.2 °C | 39.5 | 38.5 |
  | 1 | 68.2 °C | 67.4 | 68.6 |
  | 2 | 70.2 °C | 69.8 | 71.5 |
  | 3 | 72.4 °C | 69.8 | 73.0 |
  | 4 | 75.6 °C | 70.8 | 76.5 |
  | **8** | **79.8 °C** ← **hottest** | 74.6 | 80.0 |
  | 32 | 71.4 °C | 62.1 | 74.9 |

  **Temperature rises monotonically from 1 to 8 threads, then falls at 32 — and 8 threads is 8.4 °C hotter than all 32.** Mechanism: below the power cap, the boost algorithm holds near-maximum frequency *and* voltage, so each added core adds heat at undiminished voltage. At 32 threads the **ECO 105 W cap binds** (142 W PPT, 4 325 MHz), forcing voltage down across the board — which is why full load is now the *quiet* case. The board's fan curve follows **Tctl**, so it ramps hardest in the partial-load band, and ordinary desktop work — a compile, a browser, a game's worker threads — lives exactly there.

  ⚠️ **Caveat: 35 s is not thermal steady state**, and the high-power cases have more thermal mass to charge, so the 8- and 32-thread figures are understated more than the 1–4 thread ones. The 1→8 rise is robust; the exact size of the 8→32 drop is not. A 5-minute run at 8 and at 32 threads would settle it if the fan curve needs the precise numbers.

  **Decision — do NOT disable ECO Mode.** It would keep the problem and discard the benefit:
  - ECO does not touch single-core boost (measured: +0.4 % throughput, 5 360 vs 5 368 MHz), so **the surging would be identical without it**.
  - Removing it takes all-core back to 199 W, and the quiet heavy-load behaviour observed during the benchmark is the one acoustic *improvement* actually gained.

  ### ⭐ The complaint, stated precisely (operator, 2026-08-04)

  > *"More fan noise when I play an intensive game is fine, it's a willing tradeoff. My
  > main concern is daily desktop work, that my fans keep spinning up and down. During
  > normal desktop work the GPU stays silent pretty much and it's my case/AIO fans that
  > keep changing RPM that's the most annoying."*

  Three consequences, and they reorder everything:

  1. **The problem is CYCLING, not temperature.** Absolute loudness under load is
     accepted. What grates is RPM changing up and down during light work. A fix that
     lowers temperature but leaves the fans hunting solves nothing.
  2. **It is CPU-side. The GPU is irrelevant to it** — idle during desktop work. So
     GPU undervolting, GPU fan curves, and **tying case fans to GPU temperature do
     nothing for this complaint**; that last one would only act while gaming, where the
     noise is already acceptable.
  3. **Gaming noise is explicitly not a problem**, so any fix that trades quiet-under-load
     for performance is a fine trade here.

  **What actually targets the surging, in order — reordered 2026-08-04:**

  1. ⭐ **Fan-curve hysteresis / response delay** in `coolercontrol 4.3.1-2` (installed;
     `fan-control/` holds the scripts and channel labels), plus a speed floor so the fans
     do not fully drop and re-surge. **This is the direct fix and it is available today** —
     it addresses cycling itself rather than the temperature that drives it, and it
     depends on no BIOS visit, no Curve Optimizer, and none of the GPU work.
  2. **Curve Optimizer, negative.** Lowers voltage across the boost curve, and the whole
     1–8 thread band is voltage-driven with the power cap not yet binding — power density
     scales with V². It reduces the Tctl spikes that *drive* the cycling, so it makes
     hysteresis's job easier. Second because it needs a BIOS visit and a validation
     regimen, while hysteresis needs neither.

  ❌ **Deprioritised for this complaint: GPU-driven case fans.** Still worth having for
  the gaming case (measured: GPU at 575 W with the CPU idle drove Tctl from ~51 °C to
  65–72 °C via case-air heat soak before the fans responded) — but it cannot help desktop
  surging, because the GPU is not producing heat then.

  **Design the curve for the partial-load band, not for all-core.** The usual instinct is to set the knee against a full-load stress test; here that tunes against the *coolest* heavy case and leaves the fans free to scream at ~80 °C during a compile. The knee belongs around the 4–8 thread numbers above.

  ❌ **Retracted: "drive the curve from a CCD sensor rather than Tctl."** Measured as useless — under single-thread load Tctl 68.5 vs Tccd2 68.6, i.e. identical. Tctl tracks the hottest CCD closely under load, so switching sensor buys no smoothing. Hysteresis is the lever, not sensor choice.

  **Blocked until** the thermal envelope is final — curves tuned against pre-CO, pre-GPU-undervolt heat output have to be redone; see the sequencing note in the GPU item above.
- ✅ **Desktop — RTX 5090 hotspot / memory temp on Linux: SOLVED 2026-08-04. A tool exists and works on this machine.**

  **[`philipl/nvidia-gpu-sensors`](https://github.com/philipl/nvidia-gpu-sensors)** (MIT, single 772-line C file, not in AUR). It reads Core temp, **Memory temp**, **Blackwell hotspot**, and both voltage rails (NVVDD/MSVDD) through the same partially-documented `/dev/nvidiactl` RM ioctl interface the official NVIDIA tools use — reverse-engineered from `nvidia-smi`/`libnvidia-ml`, not an I²C or `/dev/mem` path.

  ```sh
  git clone https://github.com/philipl/nvidia-gpu-sensors && cd nvidia-gpu-sensors
  meson setup build && ninja -C build
  ./build/nvidia-gpu-sensors              # core + mem temp + voltages, no root
  sudo ./build/nvidia-gpu-sensors         # adds Hot Spot
  sudo ./build/nvidia-gpu-sensors --watch # 1 s refresh
  ```

  **Verified live 2026-08-04 on driver 610.43.03** (the author only claimed forward-compatibility from 595.71.05 — this closes that gap), unprivileged, at idle:

  ```
    GPU    Core Temp    Mem Temp    Hot Spot          NVVDD          MSVDD
    0         49.9 C      58.0 C         n/a        0.875 V        0.870 V
  ```

  So **memory-junction temperature reads fine** — `nvidia-smi` reports it as `N/A` purely because NVIDIA removed it from the public query surface, not because the sensor is gone. Hotspot needs root (`Hot Spot unavailable: needs root`) because RM holds non-root callers to a register allowlist that excludes `NV_THERM`.

  **Source reviewed before running (2026-08-04, all 772 lines).** Every register operation is `NV2080_REG_OP_READ_32` — **there is not a single register write in the file**; the `mmap` is `PROT_READ`; no network, no file writes, no subprocess. The Blackwell-only offsets are gated behind a chip-id check (`NV_PMC_BOOT_0 >> 20` in `0x1B0…0x1BF`) so they are never touched on other hardware. Worst realistic failure is an ioctl returning an error.

  ✅ **Installed at `~/dev/vendor/nvidia-gpu-sensors/`, pinned at commit `1775fd4`** ("nvidia-gpu-sensors: narrow hot-spot memory range", 2026-08-03) — per `~/dev/README.md`, productive third-party code lives in `vendor/`, version-pinned. Built binary verified working from that path 2026-08-04. Run it as:
  ```fish
  sudo ~/dev/vendor/nvidia-gpu-sensors/build/nvidia-gpu-sensors --watch
  ```

  **⚠️ Interface stability caveat:** this rides an undocumented ioctl ABI that has changed across driver releases. It is a diagnostic tool, not a monitoring dependency — **re-verify its output after every NVIDIA driver update**, and treat an implausible reading as the tool breaking rather than the GPU misbehaving.

  Why it matters: hotspot-minus-edge delta is what distinguishes a bad mount or dried pad from a normal load, and on a 575 W card the memory junction is the sensor that actually limits. Idle delta measured here is **8 °C** (49.9 core / 58.0 mem) — that is the baseline to compare a loaded reading against.

  ✅ **Hotspot confirmed working under root, 2026-08-04.** The NV_THERM sensor-array scan finds live sensors on this specific card — nothing further needed.

  **IDLE BASELINE (root, desktop idle, 2026-08-04) — the reference for every later comparison:**

  | Core | Memory | Hot Spot | NVVDD | MSVDD |
  |---|---|---|---|---|
  | 46.0 °C | **58.0 °C** | 50.0 °C | 0.800 V | 0.870 V |

  Two deltas worth carrying forward: **hotspot − core = 4 °C** at idle, and **memory sits 12 °C above core** — the memory junction is the hottest thing on the card even at rest, which is the expected GDDR7 picture and the reason memory temp was the sensor worth recovering.

- **Desktop — BIOS update: researched 2026-08-04, verdict DO NOT UPDATE NOW. It is the contingency if EXPO validation fails, not a preemptive action.**

  Current **1402** (2025-11-12, AGESA ComboAM5 PI 1.2.7.0). Six releases exist since, read verbatim from the [ASUS support page](https://www.asus.com/us/supportonly/rog%20strix%20b850-g%20gaming%20wifi/helpdesk_bios/) for this exact model:

  | Version | Date | AGESA | Relevant content |
  |---|---|---|---|
  | 1627 | 2026-02-11 | Pre1.3.0.0 | security; "memory compatibility for **JEDEC-compliant** modules" |
  | **1644** | 2026-03-23 | 1.3.0.0a | **"additional stability margin during high-frequency DDR5 training"**; "boot failures … on certain Ryzen 9000 configurations" |
  | 1654 β | 2026-04-27 | 1.3.0.1 | 9950X3D**2 Dual Edition** — a different SKU. **No rollback after this.** |
  | 1670 β | 2026-04-29 | — | "New memory profile support" |
  | 1681 | 2026-06-22 | 1.3.0.1b | EXPO **ULL** profiles; ECC-UDIMM performance |
  | 1686 β | 2026-07-02 | 1.3.0.1b Patch A | restores **TSME** memory encryption on Ryzen 9000 non-PRO |

  **Why not now:** no changelog anywhere in 1402→1686 mentions dual-rank, 2-DIMM, or any 6000 MT/s-specific fix. Meanwhile the machine is mid-validation with a **just-applied EXPO + ECO** config and ~a week of reboot-free uptime as the diagnostic baseline — flashing resets that baseline and injects a firmware variable into the one window whose purpose is attribution. Settings retention across a flash is **unconfirmed** (ASUS's own EZ Flash FAQ advises manually loading defaults afterwards), and OC Profile saves are version-locked by long-standing ASUS behaviour, so everything would be re-entered by hand.

  **The decision rule that makes this useful — if EXPO fails Memtest at 6000, flash 1644+ BEFORE concluding bad RAM or a damaged board.** 1644's "additional stability margin during high-frequency DDR5 training" is the one plausibly on-target item, and a memory-training firmware bug is indistinguishable from marginal hardware by symptom. This inserts a cheap step ahead of the RMA branch in section B, where getting it wrong is expensive.

  **Also relevant, not a reason to update:** 1402 itself is not clean — ASUS confirmed a memory-training bug on the sibling B850-A (4×32 GB configs locked to 3600 MT/s, DOCP/XMP boot failures, no fix timeline). That report is **4-DIMM-specific**; this machine is 2-DIMM, so it likely does not apply — but "1402 is a known-good version" is not a claim the record supports.

  **Flashing facts** (for when it happens): **not on LVFS/fwupd** — no `fwupdmgr` path, so this stays a manual job. **USB BIOS FlashBack** (rear-IO button, no CPU/RAM needed) is present, and EZ Flash 3 needs a **FAT32** stick. **Every release in this window requires renaming the `.CAP` file with ASUS's BIOSRenamer tool first** — that note appears verbatim in all six changelogs. Screenshot the EXPO/ECO/PBO pages with F12 before flashing rather than trusting OC Profile. Disconnect internal USB peripherals first — a 40-minute POST-code-D6 hang during a flash on a sibling board traced to a connected Corsair hub and AIO.

  **Not applicable here:** the AGESA 1.3.0.0+ **ECC-UDIMM 5200 MT/s cap**. The kit is `CMH64GX5M2D6000Z40` — Corsair Vengeance RGB, a consumer non-ECC line (inferred from the `CMH` part-number prefix, not a datasheet lookup); corroborated by no ECC memory controller being registered on this machine. If that inference is ever wrong, the cap would bite at 6000.

- **Desktop — ✅ LARGELY DONE (2026-08-04): GPU undervolt. Setting chosen: `1000 mV / 3000 MHz` flatten — same performance at −9.5 % power when coasting, and ~+3.9 % more work at the same 575 W when power-capped (reproduced: +4.1 %, +3.6 %).** (An earlier "+7.1 % score" claim is **RETRACTED**: it came from block comparison and inverted to −3.3 % when re-run hours later. Interleaved A/B settles it at +0.10 %, 95 % CI [−0.10 %, +0.29 %] — no measurable performance change. Power reproduced in every session.) Full ladder table, the 950 mV-vs-1000 mV margin argument, and the clock-stretching finding: [nvidia/5090-thermals.md](nvidia/5090-thermals.md) → *"RESULT: the undervolt ladder"*.

  ```fish
  sudo ./tools/gpu-flatten.sh --mv 1000 --mhz 3000   # apply (NOT persistent across reboot)
  ```

  **Key finding that changes the method — a soak cannot find the optimum.** `1000mV/3100`
  passed 4 clean passes (0 Xid, 0 device-lost) and was **3.1 % SLOWER** than 3000. The card
  reported +2.8 % clock while drawing −1.8 % power and delivering −2.2 % FPS: power tracks
  f·V², so a real clock rise must cost power — it didn't, meaning the effective clock is
  below the reported one (**clock stretching**; `nvidia-smi` keeps echoing the requested
  value). **The useful ceiling is set by score and arrives ~100 MHz before the crash.**
  Judge rungs on delivered score; reported clock is not evidence and lies at the top of the
  curve.

  ### ⚠️ The ladder is NOT finished — half the anchors were never tested

  The `950mV/3100` hard lock ended the sweep. Planned `ANCHORS="1000 950 900 875"`;
  **only 1000 and 950 ran.** `1000mV/3000` is the best setting *among what was measured* —
  it is not the sweep's answer, because the sweep did not finish.

  | anchor | status |
  |---|---|
  | 1000 mV | ✅ complete — ceiling 3100, best 3000 |
  | 950 mV | ✅ complete — ceiling 3000 (3100 hard-locked), best 3000 @ 316 W |
  | **900 mV** | ❌ **never tested** |
  | **875 mV** | ❌ **never tested** |

  **This is where the remaining power savings live.** 950 mV already delivered the same
  score as 1000 mV for **17 W less**; 900 mV may extend that, and the only reason to stop
  is a rung that cannot hold the floor clock.

  🎯 **Target from the FE guide + two AIB replies: `890 mV @ 2827 MHz`, and this is an FE.**
  The guide's author reaches 2827 at 0.890 V and states plainly that his ceiling is the
  **tool's +1000 MHz-per-node cap, not the silicon** — "0.890 is the lowest voltage which
  allows me to match stock speeds" — and that "+2827 at 0.890 is the limit for FE and some
  AIB cards." AIB corroboration: Astral OC at 0.895 V/2902 MHz, **−20 % power for <2 %
  score**; MSI Ventus at 0.9 V/2900 MHz "rock solid". `nvcurve` has the same ±1000 cap.

  On this card that target is **+825 MHz at the anchor** (base at 900 mV is **2002**), and
  it sits **inside a measured bracket**: +435 passed (`1000mV/3100`), +998 hard-locked
  (the mis-applied `900mV/3000`). So it is neither proven nor ruled out — it is the open
  question, and a bigger prize than the 17 W at 950 mV.

  ⚠️ **Compare DELIVERED clock, not requested.** The guide's own note: 2827 is only
  reached at unrealistically low temperatures; in game it runs **2670–2700**. This card's
  `1000mV/3000` requests 3000 and delivers **2802**. So 890/2827 may be ~4 % *slower*
  than the current setting while drawing far less — judge it on score, per the
  clock-stretching finding, never on `nvidia-smi`.

  ⚠️ **The queued command below BAILS at 900 mV without `--clocks`** — this already
  happened, `~/bench/explore-state.log:150`: derived floor **2800**, predicted start
  `none` (base 2002 + proven delta 435 = 2437, below the floor), hard cap 2537, and the
  explorer ended the sweep. Correct behaviour, but the output reads like an answer about
  the silicon when it is an answer about the clock list.

  ⚠️ **The ratchet CREEPS — one sweep will not reach the target.** `MAX_DELTA` rises on
  every pass (`gpu-uv-explore.sh:716`) but `DELTA_CAP` is computed **once per anchor**
  (`:609`), so each anchor can gain at most **one clock-list step** over the best delta
  proven so far. Walking 925 → 900 → 890 lifts the proven delta roughly 435 → 509 → 598,
  landing near `900mV/2600` — real progress, well short of +825. Getting further means
  re-running the sweep (it resumes and re-ratchets), not overriding the cap: the cap is
  what stopped a +998 ask on 2026-08-04, and that ask killed the machine.

  **But +825 is the wrong target.** It is the guide's *requested* clock; his delivered is
  2670–2700. Matching **2700 delivered at 900 mV is +698** — about three ratchet steps,
  and the honest goal.

  **First, repair the record** — the
  `1000mV/3100` retest passed but was run by hand, so the state file does not know, and
  without it the final selection will wrongly back `1000mV/3000` down to 2900:

  ```fish
  printf '1000mV/3100\tFINISHED\tPASS\t%s\t/home/g/bench/soak-20260804-175137\n' (date -Is) \
    | sudo tee -a ~/bench/explore-state.tsv

  # check the ladder before committing 3-4 h — writes nothing to the GPU
  sudo ./tools/gpu-uv-explore.sh --resume --dry-run \
    --anchors "925 900 890" --clocks "2500 2600 2700 2800 2900 3000"

  sudo ./tools/gpu-uv-explore.sh --resume --screen 1 \
    --anchors "925 900 890" --clocks "2500 2600 2700 2800 2900 3000"
  ```

  925 mV is in the list deliberately: it is the untested gap between the proven 950 and
  the target 890, and each rung it passes raises the ratchet that gates the next anchor.

  On resume it will ask about the unfinished `950mV/3100` rung — **answer `y`, it did crash
  the machine.**

  **READY — memory offset, never tested, and it is the untouched half.** The whole ladder
  tunes the **core** V/F curve; memory has been left at stock throughout. For LLM inference
  this is likely the larger lever, since token generation is memory-bandwidth-bound.

  - The driver-reported allowed range on a 5090 is **−1000/+3000 MHz**
    ([LACT #936](https://github.com/ilya-zlobintsev/LACT/issues/936)) — not the "+2000 max"
    several guides repeat.
  - igorslab measured **every** 5090 sample he tested holding at least +2000, best +3000,
    for only **+20–30 W** total; he treats GDDR7 memory OC as near-free.
  - A Linux compute user runs **+4400 MT/s (≈+2200 in Afterburner units)** sustained.

  ⚠️ **Judge it on delivered throughput, never on stability** — the same rule the core
  ladder already runs on, for a stronger reason. GDDR7 error correction retries a failed
  transfer instead of crashing, so a too-high memory offset shows up as **lower** tokens/s
  or a lower score with **zero** crashes and zero artifacts. That is clock stretching's
  exact shape one component over, and a stability soak cannot see it. Two contradictory
  forum claims exist about where that turnover sits; neither is verified, so **measure it
  here** rather than adopting a number. *Done when:* a memory-offset ladder measured with
  `gpu-ab-compare.sh` (games) and a fixed inference/SDXL run (compute), with the winner
  chosen by delivered work and `gpu_burn` clean for corruption.

  **Tooling — READY, both surfaced 2026-08-04 while repairing a resume by hand:**

  - **`gpu-uv-explore.sh` needs a `--state <file>` flag.** `--resume` takes the newest
    `explore-*.tsv` without a `SWEEP COMPLETE` line, so a short later run outranks the long
    sweep holding the real history — observed restoring a `+263` proven delta where the
    full ladder gives `+428`, which starts every lower anchor too low. Worked around twice
    by hand-editing state, which is the signal it belongs in the tool. *Done when:* the
    flag selects the file, `--resume` without it keeps today's behaviour, and a test case
    proves the predictor rebuilds from the named file and not the newest one.
  - **Aborting a run writes `SWEEP COMPLETE`**, so the next `--resume` says *"no unfinished
    run to resume"* and the operator must hand-delete the line. A Ctrl-C is not a completed
    sweep. *Done when:* the terminator distinguishes finished from aborted (or is written
    only on the normal exit path) and `--resume` picks up an aborted run untouched. Note
    the trap also fires on the normal path — check which before changing it.

  **Remaining (ready), in order:**
  1. **Finish the ladder at 900 and 875 mV** (above) — the open half of the sweep.
  2. **12-pass confirmation** of whatever wins.
     `sudo ./tools/gpu-flatten.sh --mv <mv> --mhz <mhz>; and sudo ./tools/gpu-soak.sh --screen 1 --passes 12`
  3. **Persistence** — save as an nvcurve profile, then a systemd unit. Nothing survives a reboot today.
  4. **Validate in a real game** — one fixed GravityMark scene is one shader mix, not a workload.
     **Marvel Rivals, run uncapped/high-fps** — not maxed-RT. The coasting high-boost
     regime is where undervolt instability lives; pinning 575 W holds the clock ~400 MHz
     *below* the failure point, which is why FurMark has never crashed this card.
     ⚠️ **Before blaming any crash on the flatten, check the two known non-GPU-setting
     failure modes** — `VKD3D_CONFIG=descriptor_heap` (five Xid 109 hangs on Aug 03, same
     signature as ours, root-caused and removed) and the open Blackwell 3–5 s presentation
     freeze (a stutter, **no Xid**). Full crash record:
     [nvidia/5090-thermals.md](nvidia/5090-thermals.md#the-complete-gpu-crash-record--and-what-it-says-about-which-load-to-test-with).
     Log the regime while playing, which also closes the open premise below:
     ```fish
     while true; nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits >> ~/bench/game-session.csv; sleep 5; end
     # afterwards:
     journalctl -b | grep -i xid
     env LC_ALL=C awk -F, '$2+0>100{n++; p+=$2; c+=$1; if($2+0>545)cap++} END{printf "%d samples under load  mean %.0f W  mean %.0f MHz  at the cap %.0f%%\n", n, p/n, c/n, cap*100/n}' ~/bench/game-session.csv
     ```

  ---

  <details><summary>Original item — READ-ONLY investigation phase (2026-08-04, now superseded)</summary>

  **Desktop — READY: GPU undervolt, READ-ONLY investigation phase first (operator decision 2026-08-04: "no setting any other voltage right now, prepare with non-destructive reading investigation").**

  Tool: **[`ekojsalim/nvcurve`](https://github.com/ekojsalim/nvcurve)** — per-point V/F curve editing via undocumented NvAPI, tested on RTX 5090/Blackwell. Why this and not `nvidia-settings` offsets: mechanism, safety analysis and the retraction of "no V/F editor exists on Linux" are in [nvidia/5090-thermals.md](nvidia/5090-thermals.md).

  **Phase 1 — look, don't change.** `uv` is already installed (`/usr/bin/uv`).
  ```fish
  uv tool install nvcurve
  sudo nvcurve setup          # 4-step compatibility check; only continue if "Compatible"
  nvcurve read --full         # dump all 128 V/F points — the actual curve
  nvcurve read --json         # same, machine-readable, for a before/after diff
  ```
  ⚠️ **`nvcurve setup` is not purely read-only.** Its third check **writes +5 MHz** to the last GPU-domain point, reads it back to confirm the driver accepted it and that no other point moved, then **auto-restores the snapshot**. Operator accepted this (2026-08-04). `nvcurve read` *is* read-only — verified by inspecting `cmd_read` in `cli.py`, which contains no write calls. Every write command also takes `--dry-run`, and snapshots are saved automatically before each write.

  **What phase 1 buys:** the real curve, on this card, on this driver. Every undervolt decision afterwards is a per-point edit against those numbers rather than a guess — and it settles the one gap the research could not: whether the undocumented NvAPI path works on **610.43.03** specifically (confirmed testing was on adjacent versions only).

  **⚠️ Session is Wayland, and that matters.** `XDG_SESSION_TYPE=wayland`, GNOME, and **no `CoolBits` anywhere in `/etc/X11/`**. The classic `nvidia-settings` offset route traditionally needs X11 with CoolBits enabled, so it is questionable on this machine — the read-only query worked, but a *write* is untested and may simply fail. NVCurve goes through NVML/NvAPI and needs no X server at all, which is an independent reason to prefer it here.

  ---

  ## ⭐ CURRENT STRATEGY (2026-08-04) — flatten, not global offset

  **The setting is a PAIR: (anchor voltage, target clock).** Everything below follows from
  that, and the earlier approaches failed because each froze one axis at a guessed value.

  **What a flatten does.** Pick an anchor voltage, set the frequency there, pin every
  higher-voltage point to that same frequency. The card then gains nothing by raising
  voltage past the anchor, so it stops — the curve becomes a **voltage ceiling**. Points
  below the anchor are untouched, so idle behaviour survives. Algorithm taken from
  NVCurve's own `frontend/src/store/curveStore.ts` (`flattenToAnchor`), not invented:
  `delta[i] = targetFreq − point[i].freq`, which makes the deltas above the anchor
  **negative**. Implemented in [`tools/gpu-flatten.sh`](../../tools/gpu-flatten.sh).

  **Why not a global offset.** It raises the *top* of the curve too — which is exactly
  what hung at +400 (top point pushed to 3 580 MHz @ 1 240 mV). A flatten caps that
  region instead, so it is never entered. The offset path is also strictly worse for the
  same clock, because it leaves the card running at 1.075 V.

  **The two steps, and why they are separate:**
  1. **Lower the voltage ceiling** — the undervolt itself. Measured: stock 1.075 V →
     anchor 1.000 V took power from **371 W to 318 W (−14 %)** but cost **126 MHz**
     (2 803 → 2 677).
  2. **Raise the target clock at that voltage** — recover the loss and ideally beat stock.
     This is what [`tools/gpu-clock-ladder.sh`](../../tools/gpu-clock-ladder.sh) walks.

  **Why the anchor is fixed at 1 000 mV first, not the 900 mV forum users run.** 1.000 V
  is *proven* on this card — NVVDD was watched sitting there rock-steady through a full
  soak, never creeping toward the 1.075 V stock uses. Jumping straight to 900 mV makes a
  failure uninterpretable: was it the voltage, or the clock demanded at that voltage?
  Characterise one axis at a known-good anchor, then step the anchor down informed.

  **The "both behaviours" property is automatic and needs no optimum — ✅ now MEASURED,
  not predicted.** A voltage ceiling means power-capped work spends the freed headroom on
  **throughput**, and unconstrained work spends it on **less power** — the card decides per
  workload. Both halves measured here on one setting: **−9.5 % power** coasting
  (`gpu-ab-compare.sh`) and **~+3.9 % more work at the same 575 W** capped
  (`gpu-capped-probe.sh`, 2026-08-04, two temperature-matched sessions). **So the two-profile scheme
  (`quiet` / `performance`) is more than is needed** — one good flatten covers both.

  ### Why the tuning measures GravityMark and only *watches* FurMark

  The same flatten has **opposite effects** depending on whether the card is power-capped:

  | Regime | Measured on this card | Effect of a lower anchor |
  |---|---|---|
  | **Coasting** — GravityMark | 2 803 MHz at **371 W of 575** | it was already as fast as its voltage allows, so less voltage means **less clock — you LOSE** |
  | **Capped** — FurMark, heavy 4K games | 2 442 MHz at **575 W pinned** | it was being held back by the power limit; less voltage per MHz lets it clock **UP inside the same budget — you GAIN** |

  **So tune in the regime where the change can hurt you.** Every stop rule — crossover,
  plateau, regression, spread — reads the **GravityMark** soak. Protect performance there
  and the capped regime can only improve, because that is the case where lower voltage is
  pure upside. **Tune for the hard case, get the easy one free.**

  FurMark is therefore *measured but never decided on*: it quantifies the free half and
  feeds no decision, by design. The measurement moved out of the explorer into
  [`tools/gpu-capped-probe.sh`](../../tools/gpu-capped-probe.sh) — inside the sweep it sat
  behind a completed 12-pass confirmation and fired **zero times** across a full day of
  laddering, so the capped half went unmeasured while the coasting half was measured six
  times. Standalone it takes four minutes. (A forum report on the same GPU claimed +7.2 %
  here; ours measures ~+3.9 % — same direction, and his card was capped at stock where ours
  is not.)

  ✅ **CLOSED 2026-08-04 — this machine runs BOTH regimes daily, so both payouts are real
  value, not one of them a curiosity.** Operator also runs **SDXL image generation and LLM
  inference** on this card besides gaming. Those pin the power limit the way FurMark does,
  so they sit squarely in the **capped** regime where the flatten pays as **throughput**.
  Gaming sits in the coasting regime and pays as **watts and noise**. One flatten, both
  halves collected — which retires the `quiet`/`performance` two-profile idea for good.

  Three consequences that do not follow from the gaming case alone:

  - **The capped-regime number is the one that matters for compute.** ~+3.9 % more work at
    the same wattage is a permanent throughput gain on every inference run.
    Independent Linux corroboration on the same card: an SDXL workload measured
    **39.3–40 s → 36.3–36.5 s** with an undervolt-plus-memory-OC
    ([Level1Techs](https://forum.level1techs.com/t/some-gpu-5090-4090-3090-a600-idle-power-consumption-headless-on-linux-fedora-42-and-some-undervolt-overclock-info/237064)).
  - **Memory offset is probably the bigger lever for LLM inference, and we have never
    touched it.** Token generation is memory-bandwidth-bound, not core-bound. See the
    memory item below.
  - **`gpu_burn` is re-promoted for this use case.** It is a weak *stability* gate (the
    power cap holds clocks low — see the crash record), but it is the only check here that
    catches **silent VRAM and compute corruption**, which for inference and image
    generation is the failure that matters: a wrong token or a subtly wrong image, with no
    crash and no artifact to see. For gaming it screens; for compute it is load-bearing.

  **Success criterion for the running ladder:** the first target whose *delivered* clock
  beats stock **2 803 MHz** while power stays near **318 W**. That is faster than stock on
  75 mV less. Expect ~120 MHz of boost derating between target and delivered — seen at
  stock too (2 803 delivered against a curve value of 2 917), so it is not a flatten
  defect.

  ⚠️ **This finds the best clock at ONE anchor, not a global optimum.** The full surface
  is anchor × clock. If a rung ≥2 900 MHz passes, stop — that is already the win, and
  chasing the true optimum means re-laddering at 950 and 900 mV for perhaps another 5 %
  power.

  **Tooling — [`gpu-uv-explore.sh`](../../tools/gpu-uv-explore.sh) is the one to run; the rest are its parts or its ancestors:**

  | Tool | Job |
  |---|---|
  | ⭐ [`gpu-uv-explore.sh`](../../tools/gpu-uv-explore.sh) | **THE RUN.** Both axes, baseline first, stops at the plateau, confirms the backed-off winner, probes FurMark at both ends. ~2.8 h unattended. |
  | [`gpu-ladder-report.sh`](../../tools/gpu-ladder-report.sh) | comparison table + computed verdict; **needs no root**, safe mid-run |
  | [`gpu-flatten.sh`](../../tools/gpu-flatten.sh) | applies one (anchor, clock) pair — used by the explorer |
  | [`gpu-soak.sh`](../../tools/gpu-soak.sh) | validates one setting at gaming clocks — used by the explorer |
  | [`gpu-clock-ladder.sh`](../../tools/gpu-clock-ladder.sh) | superseded — one axis (clock) at a fixed anchor |
  | [`gpu-flatten-ladder.sh`](../../tools/gpu-flatten-ladder.sh) | superseded — one axis (anchor) with clock frozen at stock |
  | [`gpu-uv-ladder.sh`](../../tools/gpu-uv-ladder.sh) | superseded — global-offset path, limited by the top of the curve |
  | [`test-gpu-uv-selection.sh`](../../tools/test-gpu-uv-selection.sh) | **regression test for winner selection** — no root, no hardware, ~1 s. Run it after touching `gpu-uv-explore.sh` |

  ```fish
  sudo ./tools/gpu-uv-explore.sh --screen 1     # start / Ctrl-C is a safe pause
  sudo ./tools/gpu-uv-explore.sh --resume       # continue, re-running nothing decided
  ./tools/gpu-ladder-report.sh --state ~/bench/explore-state.tsv   # progress, no root
  ```

  ### 🐛 Open bugs — fix once no sweep is running

  Bash reads a script incrementally as it executes, so **none of these get fixed while a
  run is in progress**; editing a live script can corrupt it mid-run.

  | # | Bug | Effect | Severity |
  |---|---|---|---|
  | 1 | **`run_rung` records Ctrl-C as `FAIL`** ([`gpu-uv-explore.sh`](../../tools/gpu-uv-explore.sh)) | a cancelled rung becomes a permanent false wall — the anchor is treated as bounded and that clock is never retested. Observed 2026-08-04: `1000mV/3100` marked FAIL after **158 s** of a ~670 s rung, with **0 passes, 0 device-lost, 0 Xid**. **The retest proved the FAIL false — it passes 4/4 clean.** | **corrupts results** |
  | 2 | `--status` demands root | the root check sits at line ~65, above the status branch at ~90, though `--status` only reads files | annoyance — workaround below |
  | 3 | "benchmark runs as g (root has the wrong HOME and no display access)" | reads as a warning; it is a confirmation that the privilege drop worked | cosmetic |

  **Fix for #1:** a soak killed by a signal returns 130/143 — record `INTERRUPTED`, not
  `FAIL`, and have `--resume` treat it as unproven and re-run it, exactly as it already
  does for a rung that started and never finished.

  **Workaround for #2** — the report needs no root and reads any state file:
  ```fish
  ./tools/gpu-ladder-report.sh --state ~/bench/explore-latest.tsv
  ```

  ⚠️ **A commit message on 2026-08-04 claimed #2 was fixed. It was not** — the status
  branch was moved during a rewrite and the root check was left above it. Recorded
  because an unverified fix claim is worse than an open bug: it stops anyone looking.

  ### ✅ Fixed 2026-08-04 — winner selection, now covered by a test

  Three bugs in the same block, none of which crashed: the sweep completed and printed a
  confident recommendation that was the wrong setting.

  | Bug | Would have picked | Correct |
  |---|---|---|
  | `tail -1` took whatever was recorded last | the slowest rung | — |
  | ranked by **target clock** | `1000mV/3100` — **stable but 3.1 % slower** (clock stretching) | `1000mV/3000` |
  | back-off applied **after** ranking | `950mV/2900` (untested) — demoted the winner below a rival it had beaten | `1000mV/3000` |

  The rule now: **rank by measured score**, and apply margin *before* choosing — a rung is
  preferred when a higher rung at the same anchor already passed, because that margin is
  demonstrated rather than assumed. Backing off one rung is the fallback for when nothing
  is covered, not the default.

  [`tools/test-gpu-uv-selection.sh`](../../tools/test-gpu-uv-selection.sh) pins all five
  cases against fixtures — no root, no GPU, ~1 s. It extracts the selection block from the
  live script rather than restating it, so it cannot pass while the script drifts. It
  caught a fourth bug during its own construction (equal scores resolved arbitrarily
  because there was no tie-break on clock).

  **Granularity is a resolution choice, refinable after the fact.** The default grid is
  50 mV × 100 MHz, so a true optimum at e.g. 970 mV / 2 950 MHz would never be tested.
  Coarse first is the right order — refine around the winner once it is located:
  ```fish
  sudo ./tools/gpu-uv-explore.sh --screen 1 --anchors "990 975 960" --clocks "2900 2950 3000"
  ```

  ⚠️ **The result is deliberately NOT the optimum**, on three counts, each intentional:
  the grid is coarse; it stops at the plateau rather than the maximum (which is *how* it
  avoids crashing to find the edge); and it then backs off one rung for margin. What it
  guarantees, if such a setting exists, is **coasting workloads no worse than stock** and
  **capped workloads better** — near-optimal with margin, which is the right target for a
  machine in daily use.

  ## Phase 2 — TUNE WITHOUT PERSISTING (operator decision 2026-08-04)

  **Deliberately runtime-only until proven.** Nothing survives a reboot, so the worst case is "power-cycle and it's stock again". Verified 2026-08-04: **no `nvcurve` systemd unit exists and no autoload profile is set**, and `nvcurve` writes a snapshot to `/var/cache/nvcurve/snapshots/` before every write. Persistence is a *separate, later* step (`nvcurve service install`) taken only once a setting has proven stable.

  **The edit.** A **global positive offset** shifts the whole V/F curve along the frequency axis, so every voltage point yields more clock. That is the undervolt in both directions at once: the target clock now arrives at a *lower* voltage, and the **1.075 V ceiling this card actually operates at** delivers more. Every write command accepts `--dry-run`.

  ```fish
  sudo ~/.local/bin/nvcurve write --global --delta 50 --dry-run
  sudo ~/.local/bin/nvcurve write --global --delta 50
  sudo ~/.local/bin/nvcurve read | head -20        # confirm the offsets landed
  ```
  **Step +50 → +100 → +150 → …**, re-testing at each step. Revert instantly with `sudo ~/.local/bin/nvcurve write --reset`, or reboot.

  ### How far to push, and when to stop

  Expected payoff, derived from this card's own curve points holding **2 917 MHz** (V² model — ranks correctly, magnitudes must be measured not assumed):

  | Offset | Voltage needed for 2 917 MHz | Power at that clock |
  |---|---|---|
  | stock | 1 075 mV | — |
  | +50 | ~1 047 mV | −5 % |
  | +100 | ~1 025 mV | −9 % |
  | +150 | ~1 010 mV | −12 % |
  | +200 | ~995 mV | −14 % |

  Roughly **4–5 % power per +50 MHz**, because the top of this curve is nearly flat in frequency against voltage. So **+50 alone is barely worth the trouble** — it is a safety-first first step, not a destination. Community Blackwell undervolts commonly land between **+150 and +400**; where this silicon's wall sits is unknown until measured.

  **Three rules that matter more than the final number:**

  1. **Do not live at the last stable step — back off one.** If +300 passes and +350 fails, run **+250**. Margin is needed for a hot day, a driver update, and silicon aging. The last passing setting is the *edge*, not the target.
  2. **Finer steps near the wall.** +50 while gains are obvious; **+25** once anything looks marginal.
  3. **Passing five minutes is not passing.** Instability is probabilistic — a setting can survive a short run and fail after an hour. The final candidate needs a long soak plus real gaming before it earns persistence.

  **Stop on power, not score.** The goal is the same clock at less power. If score rises *and* power rises, that is an overclock, not an undervolt — legitimate, but it costs heat, and this card converts heat back into lost clock at 2.5 MHz/°C.

  ### Three tools, each for what it is actually good at — run in this order

  **They are not redundant — each exercises a DIFFERENT block of the die.** `gpu_burn` is
  cuBLAS matrix multiplication: SMs and VRAM only. It never touches the rasteriser, ROPs,
  texture units or RT cores, so on its own it validates a path this machine barely uses
  while leaving the gaming path untested.

  | Tool | Exercises | Power | Failure appears as |
  |---|---|---|---|
  | **`gpu_burn`** | SMs, VRAM, compute | **575 W, capped** | **`GPU 0: FAULTY`** — the only detector for *silent* wrongness |
  | **FurMark Vulkan** | shaders, ROPs, texture units | **565 W, capped** | visual artifacts — renders to screen, watchable |
  | **GravityMark RT** | geometry + **RT cores** | not capped (~338 W raster) | score drop vs the 78 906 baseline, artifacts |
  | **A real game, ~1 h** | all of it, under real conditions | varies | crash, artifacts, `Xid` |

  Visual inspection is not a *better* detector than `gpu_burn` — it is the detector for a
  block `gpu_burn` cannot reach. In the graphics path errors are normally visible or crash
  outright, so watching suffices there; it is simply blind to compute, which is why the
  tool with no picture stays in the rotation.

  ```fish
  gpu_burn 300                                                    # must end "GPU 0: OK"
  furmark --demo furmark-vk --width 2560 --height 1440 --max-time 180
  sudo ./tools/gpu-thermal.sh uv-plus50 -l none -t 300            # then GravityMark RT, 2K/200K
  journalctl -b | grep -i xid                                     # must be empty
  ```

  **⚠️ `gpu_burn` is the SCREEN, not the gate — corrected 2026-08-04.** It runs first because it is cheap and because a *failure* there is definitive: a card that cannot stay correct at the easy operating point will not survive the hard one. But a **pass is weak evidence**, and the magnitude is now quantified from this card's own curve. A global offset produces a different voltage reduction depending on where the card is operating:

  | Load | Clock | Voltage stock → +400 | Reduction |
  |---|---|---|---|
  | `gpu_burn` (power-capped) | ~2 125 MHz | ~912 → ~883 mV | **−29 mV** |
  | **Gaming / GravityMark** | ~2 823 MHz | ~1 025 → ~934 mV | **−91 mV** |

  **Gaming clocks receive roughly three times the undervolt**, because this curve is flat at the top and steep lower down, so a fixed *frequency* offset becomes a much larger *voltage* drop where it is flat. `gpu_burn` is therefore not testing a slightly easier case — it is testing about a third of the stress, at a V/F point never used in practice.

  **The real gate is a load running at gaming clocks**: GravityMark RT, then actual play. `gpu_burn` still earns its three minutes for the one thing nothing else catches — silent VRAM and compute corruption, invisible to any artifact check — but its pass means "not obviously broken", never "safe to keep".

  ✅ **Confirmed the hard way, 2026-08-04: at +400 MHz `gpu_burn` ran CLEAN with zero errors, and GravityMark FROZE the machine.** Had `gpu_burn` been trusted as the gate, that offset would have shipped and hung mid-game. The screen/gate distinction is not theoretical.

  ⚠️ **And it froze PART-WAY THROUGH the run, not at startup** — which is the more important half. Instability at the wall is **probabilistic, not deterministic**: it needs the right instruction mix at the right moment on the right core, so a short clean run proves very little. Two consequences:
  - **A setting that survives 3 minutes has not been validated.** Duration is the test.
  - **Every "PASSED" in the earlier offset sweep is weak** for the same reason — 180 s of `gpu_burn` plus 120 s of FurMark, both at power-capped clocks. Short runs at the wrong V/F point.

  This is why the final gate is ~1 h of real play and not a benchmark, and why the back-off-one-step rule exists at all: the margin absorbs the runs that would have failed on a longer sample.

  ### ✅ RESULT — the wall, and the setting to keep

  | Offset | GravityMark RT (2K/200K) | Verdict |
  |---|---|---|
  | stock | **78 906** (472.5 FPS) | baseline |
  | **+250** | **81 399** (487.4 FPS) — **+3.2 %** | ✅ **stable, keep this** |
  | +300 | not tested at gaming clocks | `gpu_burn` clean only — weak evidence |
  | **+400** | **FROZE** | ❌ past the wall |

  **The +400 failure, fully characterised (2026-08-04):**
  ```
  E:  2:40.845: VK::error(): device lost          ← GravityMark, ~2m40s into the run
  kernel: NVRM: Xid (PCI:0000:01:00): 109, pid=446324, name=GravityMark.x64,
          channel 0x0000001b, errorString CTX SWITCH TIMEOUT, Info 0x5c01a
  ```
  **Xid 109 / CTX SWITCH TIMEOUT** — a shader hung and the GPU could not complete a
  context switch. The textbook signature of an unstable V/F point, and **no visual
  artifact preceded it**: the failure mode here is a hang, not corruption. Artifact-
  watching would not have caught this either; only running the load did.

  **Why the offset pays in this workload — the operating point at +250:**
  ```
  Frequency 3.04 GHz   Power 386.6 W   Temp 74 °C   Fan 47 %   Utilisation 94 %
  ```
  **386 W of a 575 W limit — 190 W of unused headroom.** The card is nowhere near its
  power cap here; it is limited by how much clock it can get per volt. That is exactly
  the regime a curve offset addresses, and it is why the same offset produced ~3 % here
  and nothing measurable under `gpu_burn` and FurMark, both of which pin 575 W. The
  earlier "the gain is noise" reading came from measuring only in the regime where no
  gain is possible.

  (Utilisation 94 %, not 100 %, so a small non-GPU bottleneck exists — not investigated.)

  **The wall is between +300 and +400. Take +250.** It already delivers the full ~3 %, and per the back-off-one-step rule the last *passing* setting is the edge rather than the target — +300 rests only on the weak test that +400 just discredited.

  **The ~3 % is corroborated by a second workload once temperature is controlled.** `gpu_burn` GFLOP/s looked flat across offsets, but that comparison was temperature-confounded — each sweep step started hotter than the last. Matched by temperature: **67 915 at +400/72 °C vs 65 681 at +50/71 °C (+3.4 %)**, and **64 595 at +400/87 °C vs ~63 000 at +50/86 °C**. Same ~3 % GravityMark showed, from an independent load.

  ⚠️ **Not thermal throttling, at any point.** Throughput falling with heat (70 237 → 64 595 GFLOP/s across 65 → 87 °C, −8 %) is **leakage at a fixed power budget**: `SW Power Cap: Active`, `HW/SW Thermal Slowdown: Not Active`, lifetime counter **0 µs**. Throttling steps; leakage declines smoothly. This card has never thermally throttled.

  **⚠️ GravityMark alone is not a stability test.** It never approaches the power limit (338 W of 575 in rasterization) because it is geometry-bound, not power-bound. It scores well and runs cool — useful for measuring gain, useless for finding instability.

  **Read power, not only score.** A genuine undervolt shows **the same or better score at LOWER power**. If power rises with the score, that is an overclock rather than an undervolt — still a legitimate outcome, but it costs heat, and on this card heat costs 2.5 MHz/°C back.

  **Failure signature:** `FAULTY`, a visual artifact, or any `Xid` in the journal → back off one step. Instability appears **under load, not at idle** ([nvidia/5090-thermals.md](nvidia/5090-thermals.md)), which is what makes this deterministically testable rather than a wait-and-see.

  **The real gate is a game, not a benchmark.** Once all three synthetic tests pass, ~1 h of actual play (Marvel Rivals is installed) is the test that decides — mixed, bursty, real conditions that synthetic loops do not reproduce, on the exact path this machine is used for. Check `journalctl -b | grep -i xid` afterwards.

  **Persist only after a step survives all three synthetic tests AND a real gaming session**, and record which offset was proven before installing the service.

  **Later refinement:** the global offset is the blunt instrument. The precise undervolt — pick a voltage point, raise its frequency, flatten the points above so the card never exceeds that voltage — needs the web UI's flatten tool, and preserves idle behaviour by leaving the low points untouched. Worth doing once these steps have established how much headroom the silicon has.

  </details>

- **Desktop — READY: tie case fans to GPU temperature as well as CPU (operator wants to explore this, 2026-08-04).**

  **The gap, measured not assumed:** case fans are driven from CPU temperature only, so a GPU-only load — the common case in gaming — gives them no reason to ramp. With the GPU at **575 W and the CPU idle**, CPU Tctl rose from ~51 °C to **65–72 °C purely from case-air heat soak** before the fans responded. They did eventually reach 1 523 rpm, but only *after* the GPU's heat had reached the CPU: a lagging, indirect response to the wrong sensor.

  ✅ **Confirmed available — nothing to install.** The running `coolercontrold 4.3.1-2` already enumerates the card as its own device:
  ```
  GPU    NVIDIA GeForce RTX 5090
  CPU    AMD Ryzen 9 9950X3D 16-Core Processor
  Hwmon  nct6799            ← fan1 case / fan2 AIO / fan7 pump
  ```
  (Queried via the daemon API at `localhost:11987`; procedure and channel labels in [fan-control/coolercontrol-labels.md](../../fan-control/coolercontrol-labels.md).)

  **Design: a Mix profile taking the MAX of CPU and GPU temperature**, not a replacement of the CPU source. Replacing it would trade one blind spot for the other — a CPU-only compile load is the *hottest* thing the CPU does (79.8 °C at 8 threads, above the all-core figure) and must still drive the fans.

  **Sequencing:** after ECO/CO and the GPU undervolt are settled — a curve tuned against the current thermal envelope has to be redone once either changes. Background and the measured numbers: [nvidia/5090-thermals.md](nvidia/5090-thermals.md).

  **Done when:** a GPU-only load (`sudo ./tools/gpu-thermal.sh <label>`) ramps the case fans without waiting for CPU heat soak, verified by comparing the `case_rpm` column against the `gpu-stock` run's lag.

  ⚠️ **Basis for the general idea is community consensus** — no controlled study found. The *specific* lag above is measured on this machine, which is what justifies the work.

- **Desktop — READY: GPU stress test, to be run alongside `nvidia-gpu-sensors --watch`.** The point is not "does it crash" but capturing **hotspot-minus-core under sustained load** — the delta that reveals a bad mount or dried thermal pads, and which is **4 °C at idle** on this card (measured 2026-08-04, once the root hotspot read worked; an earlier version of this line said 8 °C, which was the memory−core delta from before hotspot was readable). Three load types, because they stress different things:

  | Tool | Install | Run | What it loads |
  |---|---|---|---|
  | `gpu-burn` | AUR `gpu-burn-git` | `./gpu_burn 600` | cuBLAS compute power-virus — highest sustained power draw |
  | FurMark 2 | AUR `furmark` | GUI / OpenGL + Vulkan stress | graphical power-virus, exercises the render path |
  | Unigine Superposition | AUR `unigine-superposition` | GUI benchmark | realistic game-like load, closest to actual use |

  Setup, once:
  ```fish
  yay -S gpu-burn-git
  mkdir -p ~/bench
  command -v gpu_burn gpu-burn      # confirm the installed binary name before relying on it
  ```
  Protocol — three terminals, load running ≥10 minutes so the heatsink actually reaches steady state (the first 2–3 minutes tell you nothing):
  ```fish
  # terminal 1 — the sensors nvidia-smi cannot show
  sudo ~/dev/vendor/nvidia-gpu-sensors/build/nvidia-gpu-sensors --watch

  # terminal 2 — power/clocks/util logged to file
  nvidia-smi dmon -s pucvmet -o DT -f ~/bench/gpu-stock.csv

  # terminal 3 — the load
  gpu_burn 900     # or FurMark / Superposition
  ```
  ⚠️ `gpu_burn` vs `gpu-burn` — **unverified which name the AUR package installs**; upstream's own binary is `gpu_burn`, built in-tree, so a from-source build is run as `./gpu_burn`. Check with the `command -v` line above rather than assuming.
  **Compare against the idle baseline above** (core 46.0 / mem 58.0 / hotspot 50.0). What to read:
  - **hotspot − core delta.** Idle it is 4 °C. A modest rise under load is normal; a *disproportionate* one is the signature of poor die contact — a bad mount, pump-out, or dried paste.
  - **memory temperature**, already the hottest sensor at idle. On a 575 W card this is what actually throttles.
  - **the `pwr` column** — do not assume the load saturates the card, read what it draws.

  **Do this BEFORE the GPU undervolt**, for the same reason as the CPU baseline: the stock thermal signature is not recoverable afterwards.

  ⚠️ **No verified thresholds.** Commonly cited figures (hotspot delta under ~15 °C healthy, GDDR7 limit around 105 °C) are community numbers this repo has **not** confirmed against a primary source — treat the idle deltas above as the real reference and judge by change, not by an absolute number pulled from a forum.
- **NVMe firmware — desktop surveyed 2026-08-03, verdict: flash nothing for now.** Routine maintenance, not surge-specific. Re-check every few months, or when a drive misbehaves.

  | Drive | Node | Installed FW | Verdict |
  |---|---|---|---|
  | Samsung 990 PRO 4TB | `nvme0n1` | `4B2QJXD7` | `8B2QJXD7` (Dec 2025, "read-op stability") reported available — **single-sourced, verify before flashing** |
  | Samsung 990 PRO 2TB | `nvme1n1` | `0B2QJXG7` | current; different firmware LINE, see below |
  | Samsung 9100 PRO 4TB | `nvme2n1` | `0B2QNXH7` | current — **do NOT flash `1B2QNXH7`** |

  - **`1B2QNXH7` for the 9100 PRO is a known-bad release.** Pushed via Magician 2026-07-20, withdrawn by Samsung days later after drives vanished from BIOS/OS; no user reflash tool for this model, affected owners were routed to RMA. This is also the **root drive** (`/` is btrfs on `nvme2n1p2`) — so snapper snapshots live on the very device a bad flash would kill. **"Snapshot before flashing" does not cover this drive**; it needs an off-drive backup, and it is the drive with the least reason to be touched.
  - **`JXD7` vs `JXG7` are different firmware lines, not versions.** The 6th character encodes a NAND/hardware line (V7 vs V8 NAND per secondary sources; no primary Samsung doc found). `0B2QJXG7` is **not** "older than" `4B2QJXD7` — do not compare them or cross-flash. The leading character *is* a sequential counter within a line.
  - **990 PRO health-counter bug — checked, not present.** Launch firmware `0B2QJXD7` miscalculated SMART Available-Spare, causing false rapid health decline; `1B2QJXD7` (Feb 2023) stopped further decline but never reset already-inflated counters, so a drive that passed through it stays pessimistic forever. Measured 2026-08-03: `nvme0` Available Spare **100%**, wear 3% — that is the exact counter the bug attacked, untouched. Cross-checked against writes, which is the test that doesn't depend on knowing the shipped firmware: 98.2 TB written over 4 868 power-on hours is ~4% of the 4TB model's rated endurance, so reported wear (3%) sits at or *below* the write-derived estimate — the opposite of an inflated counter, and the conclusion holds even if the exact TBW rating is off. This drive was never affected, whatever its firmware history. Closed; don't re-derive.
  - **LVFS is a dead end here — confirmed on fresh metadata 2026-08-03.** `fwupd 2.1.6` enumerates all three with proper GUIDs but carries no releases: after `fwupdmgr refresh`, all three still land under "Devices with no available firmware updates", and `fwupdmgr get-releases` fails on each. 990 PRO family updates via Samsung's bootable ISO (no Windows needed); the 9100 PRO has **no ISO** — Magician (Win/macOS) only, i.e. not Linux-viable.
  - Standing rules for any future flash: back up (off-drive for whatever carries `/`), never flash over a USB adapter, one drive at a time, and **never flash mid-hardware-investigation** — it adds a variable to exactly the signal the surge check is reading.
  - Laptop: not yet surveyed. Once anything is actually applied, graduate to `hardware/nvme-firmware.md` + a README index row.
- **Both machines — `fwupdmgr` cadence + one pending item.** `sudo fwupdmgr refresh && sudo fwupdmgr get-updates` is read-only (metadata download + listing; `fwupdmgr update` is the part that flashes) — safe to run monthly or before/after a BIOS change. Desktop as of 2026-08-03: 11 devices updatable, no SSD or System Firmware releases, one **pending** — UEFI dbx `20250902 → 20260402`, urgency High, CVE-2026-8863. **Secure Boot is disabled on the desktop** (`bootctl status`, 2026-08-03) — so the revocation list is not consulted at boot: the update is inert *and* riskless here. The brick scenario (a dbx revoking the running bootloader's signature) requires Secure Boot enabled; it does not apply. Apply it anyway when convenient — `sudo fwupdmgr update`, needs a reboot — because it clears the only pending entry, which keeps future `get-updates` output signal rather than noise, and pre-positions the machine if Secure Boot is ever turned on. `mokutil` is not installed; use `bootctl status | grep -i "secure boot"`.
- **Desktop — PARKED: one recent freeze, cause unknown.** Deliberately not diagnosed yet (operator: track it, don't investigate now). **Still open as candidate causes, none re-verified:** ⚠️ **NVIDIA GSP-RM heartbeat timeout on S3 resume** ([issues/known-issues.md](issues/known-issues.md)) — the strongest lead by symptom match: documented on this exact GPU, freezes ~1 s after wake, requires a hard power cycle, and is recorded as having **no confirmed workaround**. Written against driver 595.45.04; the machine now runs 610.43.03 and it has not been re-tested — so it is neither known-broken nor known-fixed. Also: spd5118 suspend abort ([system/sleep.md](system/sleep.md)), RTX 5090 + IOMMU ([nvidia/rtx5090-iommu.md](nvidia/rtx5090-iommu.md)), GPU hang (`tools/gpu-hang-watch.sh` — written for Marvel Rivals specifically, so its Xid watch is narrower than "any freeze"). Each has a fix documented as applied; whether it still fires is unchecked, and "documented as applied" is not the same as "verified working" — the doc says what was done, the machine says what happens. Missing evidence to unpark: the journal around the event — `journalctl -k -b -1 -e` (or `-b -2`) run soon after, plus what the machine was doing (idle/sleep, gaming, desktop). Journald persistence is **confirmed on** (`/var/log/journal/` exists with a machine-id dir, 2026-08-03), so a hard power-cycle still leaves the previous boot readable via `-b -1` — the evidence survives the freeze. Also worth knowing before testing: the active sleep mode is **`deep` (S3)**, not s2idle (`/sys/power/mem_sleep` → `s2idle [deep]`), i.e. exactly the mode with the documented hard-lock. Does **not** implicate the drives — SMART clean on all three (above).

  **✅ THE MISSING EVIDENCE, SUPPLIED BY THE OPERATOR 2026-08-04: the freeze happened under GPU LOAD.** Not at idle, not on resume. This was the field listed above as unknown, and it re-ranks the whole candidate list:

  | Candidate | Symptom it explains | Verdict against GPU-load |
  |---|---|---|
  | **GPU hang / Xid** (`tools/gpu-hang-watch.sh`) | freeze under sustained GPU load | **← now the leading candidate** |
  | **RTX 5090 + IOMMU** ([nvidia/rtx5090-iommu.md](nvidia/rtx5090-iommu.md)) | DMA faults under load | **plausible, keep** |
  | NVIDIA GSP-RM heartbeat | freeze ~1 s after **S3 resume** | demoted — wrong trigger |
  | spd5118 suspend abort | suspend path only | demoted — wrong trigger |
  | PCIe Gen 5 NVMe ASPM | freeze at **idle / low load** | demoted — wrong trigger (see below) |

  **Next evidence to collect** (unchanged in kind, now much better targeted): after the next freeze, `journalctl -k -b -1 | grep -iE 'xid|nvrm|gpu|hardware error'` — an Xid number names the failure class directly. **Grep, never `tail`:** UFW logs blocked multicast (router IGMP + IPv6 router-solicit) every ~2 minutes, so a plain `dmesg | tail` on this machine is ~90% firewall noise and will bury the one line that matters — observed 2026-08-04 while hunting an injected MCE. `tools/gpu-hang-watch.sh` already exists but was written for Marvel Rivals specifically, so its watch is narrower than "any GPU-load freeze"; widen it before relying on it.

  **⚠️ Correction, 2026-08-04.** This entry previously carried a PCIe Gen 5 NVMe/ASPM lead, described as matching "better than anything else on this list" because the forum report it came from was titled *freezes at idle / low load*. **That symptom was the forum thread's, never this machine's** — the "what was the machine doing" field was recorded right here as missing evidence, and the lead was written as though it had been answered. A candidate's own symptom is not evidence about the case it is being matched to. Retained only as a hardware note, since the matching hardware is genuinely present and it may matter later if an **idle** freeze ever does occur: `nvme2` (Samsung 9100 PRO 4TB) links at **32.0 GT/s ×4 (Gen 5)** while `nvme0`/`nvme1` (990 PRO) run Gen 4; ASPM policy is `[default]`. Sources: [initial](https://rog-forum.asus.com/t5/amd-800-series/bug-report-system-freezes-at-idle-low-load-asus-x870e-h-ryzen-9/td-p/1141620), [root cause](https://rog-forum.asus.com/t5/amd-800-series/update-x870e-h-9950x3d-idle-freeze-pcie-gen-5-nvme-root-cause/td-p/1146380).
- **Desktop — NEXT BIOS VISIT: ordered checklist.** Already verified from Linux, do **not** change: **Resizable BAR ON** (`nvidia-smi` BAR1 = 32768 MiB ≈ full VRAM; 256 MiB would mean off), **PCIe Gen 5 × 16** at max, `iommu=pt` on the cmdline ([nvidia/rtx5090-iommu.md](nvidia/rtx5090-iommu.md)). So Above 4G Decoding / ReBAR are correct already.

  **✅ APPLIED 2026-08-04** — read off the *Save Changes & Reset* confirmation screen (photographed), which is the authoritative diff of the visit:

  | Setting | From | To |
  |---|---|---|
  | Ai Overclock Tuner | Auto | **EXPO I** |
  | Memory Frequency | Auto | **DDR5-6000** |
  | Tcl / Trcd Wr / Trcd Rd / Trp / Tras | Auto | **40 / 50 / 50 / 96** |
  | DRAM VDD / VDDQ, Memory VDD / VDDQ | Auto | **1.35 V** |
  | PMIC Voltages | Auto | Sync All PMICs |
  | When system is in working state | **Aura Off** | **All On** |
  | Precision Boost Overdrive | Auto | **Advanced** |
  | ECO Mode | Auto | **105 W** |

  **The board does offer a 105 W tier** — the manual's 65 W-only listing was
  generic-doc noise, so the PPT=142 W manual fallback in section C was not needed.
  Timings match the kit's rated 6000 CL40, i.e. EXPO I loaded the profile it should.

  **⚠️ Curve Optimizer was NOT set.** PBO is on `Advanced`, which only *exposes*
  the CO submenu — no offsets appear in the diff, so all cores remain at 0.
  Current state is therefore **stock + EXPO + ECO**, and the per-core `mprime`
  regimen (step 2 of the test suite) has nothing to validate yet.

  **⚠️ This breaks the single-variable benchmark comparison.** The stock baseline
  ran at **4800 MT/s**; the machine is now at **6000**. `stress-ng --matrix` is
  memory-bandwidth sensitive, so an ECO-vs-stock delta taken now measures
  *ECO + EXPO together* and cannot separate them. Label the run **`eco-expo`**,
  not `eco`. To recover the isolation later, run a third pass with ECO returned to
  Auto and EXPO left on — that yields the EXPO-only delta, and ECO falls out by
  subtraction. Cheap, and it does not sacrifice the EXPO setting.

  **Navigation:** `F7` toggles EZ ↔ Advanced Mode. **`F9` opens search** — type the setting name and jump straight to it; this beats memorised paths, which shift between BIOS revisions. `F3` = My Favorites (collect settings on one page). `F10` save+exit. Paths below are the expected ASUS ROG layout — **verify against the screen, don't trust them blindly**.

  **A — set these now, none of them confound anything:**
  1. ✅ **RGB lighting — DONE, and it was the whole cause.** `When system is in working state` was **`Aura Off`**; set to **`All On`** and the board LEDs and RGB fans came back. That is why every OpenRGB write succeeded and changed nothing — the gate was in hardware, below anything OpenRGB could observe or report. Mechanism, options table and the RAM/GPU-still-work tell: [nvidia/openrgb.md](nvidia/openrgb.md). **Still open at the next visit:** the *second* toggle (*sleep, hibernate and soft-off states*) was not in the diff, so its value is unknown — and `Advanced → APM Configuration → ErP Ready` was not checked either. If **Enabled**, ErP cuts standby power to the RGB rails and is the candidate cause for "RGB not restored after sleep" ([issues/known-issues.md](issues/known-issues.md)); set **Disabled** to test that.
  2. **Memory Context Restore = Enabled** — `Advanced → AMD CBS → UMC Common Options → DDR Options` ✅ **confirmed in the ASUS 800-series BIOS manual** (`Power Down Enable` sits alongside it). Without it AM5 re-trains memory on every cold boot — the 30–60 s delay. Expect one slow boot after changing it.
  3. **CSM = Disabled** — `Boot → CSM (Compatibility Support Module) → Launch CSM`. **Fast Boot = Disabled** — `Boot → Fast Boot`; makes USB enumerate reliably at POST, which matters while the USB-port sweep is open.
  4. **Confirm, do not change:** `Advanced → PCI Subsystem Settings → Above 4G Decoding` and `Re-Size BAR Support` both **Enabled** — already verified ON from Linux, just don't let anything reset them.
  5. ❌ **No built-in memory test on this board** — the `Tool` menu holds only EZ Flash 3, Secure Erase, Q-Dashboard, User Profile, SPD Info, MyHotkey, DriverHub (ASUS 800-series BIOS manual). Don't hunt for it. Memtest comes from `sudo pacman -S memtest86+-efi` and appears in the boot menu — no removable media needed either way.
  6. **Clear CMOS is a rear-IO push-button** on this board (confirmed, Quick Start Guide rear-panel diagram) — not a jumper. That's your recovery if EXPO won't post.

  **B — the RAM sequence. EXPO first (operator decision 2026-08-03), with a branch that keeps failures attributable:**
  5. **Enable EXPO** → `Ai Tweaker → Ai Overclock Tuner` → set **EXPO I** (not Tweaked). The kit is `CMH64GX5M2D6000Z40`, 2×32 GB dual-rank, rated **6000 CL40** — confirm the profile it loads reads 6000. (EZ Mode also has a one-click D.O.C.P./EXPO toggle if you prefer.) Do this **last** among the BIOS changes — a failed EXPO boot may need a CMOS clear, which wipes section A with it.
  6. Run **Memtest86+ overnight, ≥4 full passes**.
     - **Passes** → done. Board *and* RAM cleared at the harder setting; keep 6000. A clean run at EXPO is a stronger result than one at JEDEC, which is why this order is worth taking.
     - **Fails** → drop to **JEDEC 4800** and memtest again. That one extra run restores the separation EXPO-first gives up:
       - JEDEC passes → EXPO was too aggressive → try **5600**, then **5200** (already proven stable with EXPO on this system).
       - JEDEC **also** fails → it is the RAM or the board — that is the surge signal, escalate to the RMA decision.
  7. **Expect a slow first EXPO boot:** 1–5 minutes of black screen with fans spinning is memory training on 64 GB dual-rank, not a dead board; it may self-power-cycle. Only if it truly will not post, clear CMOS (rear-IO button). **Note what EXPO sets** — frequency, timings, VDD/VDDQ, SoC voltage — before leaving the screen, so stepping down to 5600 manually is possible without re-picking a profile.
  8. `rasdaemon` (now running) is the backstop for marginal-but-passing EXPO: corrected errors land in `ras-mc-ctl --errors` and persist across reboots. Baseline as of 2026-08-03 is **no errors in any class**.

     ⚠️ **That baseline is half-blind — the instrument was never proven live (found 2026-08-04).** `ras-mc-ctl --errors` reports two lanes and only one of them has a source on this machine:
     - **MCE lane — live.** `journalctl -k` shows `MCE: In-kernel MCE decoding enabled` and `RAS: Correctable Errors collector initialized`. "No MCE errors" is a real negative.
     - **Memory/EDAC lane — DEAD.** `/sys/devices/system/edac/mc/` contains **no `mc0`**, i.e. no memory controller is registered. `amd64_edac` exists as a module (`/lib/modules/7.1.5-1-cachyos/kernel/drivers/edac/amd64_edac.ko.zst`) but is **not loaded** — `lsmod` shows nothing matching `edac`. So "No Memory errors" is what a dead lane returns, indistinguishable from a true absence.

     **Resolved 2026-08-04: the EDAC lane is permanently unavailable on this machine. Do not re-try it.**
     ```
     $ sudo modprobe amd64_edac
     modprobe: ERROR: could not insert 'amd64_edac': No such device
     $ ls /sys/devices/system/edac/mc/     # power  subsystem  uevent — no mc0
     ```
     `No such device` is the driver reporting it found no memory controller it supports — not a missing module, not a misconfiguration. This CPU is **family 26 (0x1A = Zen 5, model 68)** per `/proc/cpuinfo`, and this kernel's `amd64_edac` does not claim its UMCs. Nothing to fix; the only action is to read the output correctly from now on.

     **What this does and does not cost.** The `Memory errors` table in `ras-mc-ctl --errors` is dead here, so **its "No Memory errors" line carries no information — never quote it as evidence of health.** DRAM corrected errors on Zen are delivered as **MCA events from the UMC banks**, decoded in-kernel (`MCE: In-kernel MCE decoding enabled`) with `amd_atl` (present: `/lib/modules/…/drivers/ras/amd/atl/amd_atl.ko.zst`) translating a normalized address back to a DIMM — that path is independent of EDAC. So memory-error *detection* is expected to survive; what is lost is the per-DIMM EDAC table.

     ⚠️ **That last paragraph is reasoning, not a measurement — the MCE lane has not been shown live on a real error.**

     **`ras-mc-ctl --summary` cannot answer this, and 2026-08-04 proved it can't.** Run on this machine it returns:
     ```
     No Memory errors.      ← lane is DEFINITIVELY DEAD (no EDAC MC exists)
     No PCIe AER errors.
     No ARM processor errors.
     No Extlog errors.
     No devlink errors.
     No MCE errors.         ← lane believed live — reported IDENTICALLY
     ```
     A lane known to be dead and a lane believed live produce the same sentence. That makes the whole summary worthless as evidence of liveness, for every lane — including the ones that look reassuring. (`No ARM processor errors` on an x86 machine is the same joke, more obviously.)

     **The only thing that settles it is making the lane go red on a planted error.** Kernel support is present — `CONFIG_X86_MCE_INJECT=m` and `CONFIG_ACPI_APEI_EINJ=m` (`/proc/config.gz`, checked 2026-08-04) — so the modules exist:
     - `/lib/modules/7.1.5-1-cachyos/kernel/arch/x86/kernel/cpu/mce/mce-inject.ko.zst`
     - `einj` (ACPI APEI error injection), currently unloaded — `/sys/firmware/acpi/einj` does not exist

     ❌ **The userspace `mce-inject` tool is NOT packaged for Arch — not in the repos, not in the AUR** (`yay -S mce-inject` → "No AUR package found"). An earlier note here called it "AUR-only"; that was inferred from `pacman -Qo` returning no owner, which only proves it is not installed. Upstream is [`andikleen/mce-inject`](https://github.com/andikleen/mce-inject), buildable from source. **Not needed** — the kernel's own debugfs interface does the job.

     ❌ **ACPI EINJ is unavailable on this board (2026-08-04).** `einj` loads as a module but `/sys/firmware/acpi/einj` never appears — the firmware ships no EINJ tables. Normal for a consumer board. Don't re-try it.

     ✅ **`mce-inject` debugfs interface is live** (`mce_inject` loaded, 2026-08-04), and it is the SMCA-aware variant — `ipid` and `synd` are AMD Scalable-MCA fields, so an injected error can be shaped like one from a real UMC bank:
     ```
     /sys/kernel/debug/mce-inject/  → addr bank cpu flags ipid misc README status synd
     /sys/kernel/debug/mce/         → fake_panic severities-coverage
     ```
     Read `/sys/kernel/debug/mce-inject/README` for field semantics (it is on the machine; note **`ls` and `cat` here need `sudo` themselves** — `/sys/kernel/debug` is mode `0700`, and `sudo modprobe … ; ls …` leaves the `ls` unprivileged).

     **The test — `sw` mode, corrected error, safe by the README's own words** ("Software error injection. Decode error to a human-readable format only. Safe to use."). **Writing `bank` triggers the injection, so it goes last:**
     ```fish
     echo sw                 | sudo tee /sys/kernel/debug/mce-inject/flags
     echo 0x9400000000000135 | sudo tee /sys/kernel/debug/mce-inject/status
     echo 0x0010000000       | sudo tee /sys/kernel/debug/mce-inject/addr
     echo 0                  | sudo tee /sys/kernel/debug/mce-inject/cpu
     echo 0                  | sudo tee /sys/kernel/debug/mce-inject/bank    # ← triggers
     ```
     Status word, bit by bit — the two that matter for safety are the ones left **clear**:

     | Bit | Name | Set? | Why |
     |---|---|---|---|
     | 63 | VAL | **1** | else the entry is ignored entirely |
     | 61 | UC | **0** | **corrected**, not uncorrectable |
     | 60 | EN | **1** | error reporting enabled |
     | 58 | ADDRV | **1** | `addr` above is meaningful |
     | 57 | PCC | **0** | **PCC=1 is what panics the machine** |
     | 15:0 | MCACOD | `0x0135` | the error code; **arbitrary for this test** — what is being proven is that *an* MCE reaches the collector, not that a specific error type decodes correctly |

     `fake_panic` is **not** needed for `sw` — it exists for `hw` mode, which raises a real #MC exception. Do not use `hw`.

     **Reading the result — this is what makes the outcome unambiguous:**
     ```fish
     sudo dmesg | tail -20
     sudo ras-mc-ctl --errors
     ```

     | dmesg | ras-mc-ctl | Conclusion |
     |---|---|---|
     | shows it | shows it | ✅ **lane live** — clean results become real evidence |
     | shows it | silent | ❌ **rasdaemon is not collecting** — the finding this test exists for |
     | silent | silent | inconclusive — encoding or trigger wrong, **not** proof of a dead lane; adjust and retry |

     That third row is why both readouts are taken: the kernel decoder prints on `sw` injection independently of rasdaemon, so `dmesg` separates "the injection didn't happen" from "the collector didn't catch it". Without it, a bad status word would look exactly like a dead collector.

     ---

     ## ✅ RESULT 2026-08-04: the MCE lane is LIVE — proven, not assumed

     The injection landed in both places. Kernel decoder:
     ```
     mce: [Hardware Error]: Machine check events logged
     [Hardware Error]: Corrected error, no action required.
     [Hardware Error]: CPU:0 (1a:44:0) MC0_STATUS[-|CE|-|AddrV|-|-|-|-|-|-]: 0x9400000000000135
     ```
     `CE` and no `PCC` — corrected, no panic, exactly as the status word was built. And `ras-mc-ctl --errors`, which had never printed anything but "No … errors", now shows:
     ```
     MCE events:
     1 2026-08-04 09:36:00 +0200 error: Corrected error, no action required., CPU 2,
       bank Unified Memory Controller V2 (bank=0), mca DRAM ECC error …
       status=0x9400000000000135, addr=0x10000000
     ```

     **Three things this settles:**

     1. **rasdaemon is collecting.** A clean `MCE events` result is now real evidence. This is the one lane the EXPO/CO validation actually rests on, and it is the only instrument in this repo that has been shown to go red on a planted defect.
     2. **The dead EDAC lane costs nothing for memory-error detection — now measured, not inferred.** rasdaemon classified the injected error as a **DRAM ECC error** and still filed it under **`MCE events`**, while `No Memory errors.` printed unchanged directly above it. So a real DRAM ECC error arrives in the MCE table, not the Memory table. The earlier note reasoned this from the Zen MCA architecture and flagged itself as unverified; it is now demonstrated.
     3. **`ras-mc-ctl --summary`'s uniform "No … errors" really was hiding a working lane**, not just a broken one — which is exactly why the output was worthless in both directions.

     ⚠️ **The database now contains a synthetic error. Do not read it as hardware history.** The event timestamped **2026-08-04 09:36:00 +0200, bank=0, addr=0x10000000, status=0x9400000000000135** is the injected one. Any *later* MCE event is real. Superseding the 2026-08-03 "no errors in any class" baseline: **new baseline is 1 synthetic MCE, 0 real.**

     Two cosmetic discrepancies, noted so they are not mistaken for findings later: rasdaemon reports `CPU 2` where the injection specified and the kernel logged `CPU:0`; and rasdaemon labels bank 0 `Unified Memory Controller V2` while the kernel decoder calls it `Load Store Unit`. The latter is because SMCA bank identity comes from `IPID`, which was left at `0` — rasdaemon maps HWID 0 to UMC. Neither affects the result; both would matter if a *real* event's bank attribution ever needed trusting, in which case set `ipid` deliberately.

     Until that has gone red once, treat **every** clean `ras-mc-ctl` result in this repo — including the 2026-08-03 baseline above — as *unproven*, not as evidence of health.

  **C — CPU tuning. Paths, per the ASUS 800-series BIOS manual (E25269):**
  - **Curve Optimizer — path CONFIRMED from the live screen 2026-08-04** (photographed), not from the manual: `Advanced → AMD Overclocking → AMD Overclocking → Precision Boost Overdrive → Curve Optimizer`. Note `AMD Overclocking` appears **twice** in the breadcrumb; that is the real path.

    **⚠️ The trap: `All Core Curve Optimizer Sign` defaults to `Positive`.** The submenu has three fields, and the sign field is separate from the magnitude field. Typing `15` into Magnitude while Sign still reads `Positive` gives **+15 — an OVERVOLT**, the exact opposite of the intent, and it will look like it worked because the machine boots and benches fine. **Set Sign = `Negative` FIRST, then the magnitude, then re-read both before leaving the page.**

    **Settings to apply:**

    | Field | Set to |
    |---|---|
    | Curve Optimizer | `All Cores` |
    | All Core Curve Optimizer Sign | **`Negative`** ← change this first |
    | All Core Curve Optimizer Magnitude | **`15`** |

    Magnitude is in counts of roughly 3–5 mV, so −15 ≈ −45…−75 mV. **This is the same operation as a GPU curve undervolt, expressed in the mirror** — AMD labels the voltage axis, NVIDIA the frequency axis, and both ask the silicon to beat its validated V/F point. Comparison table, including why CO is the riskier of the two to live with: [nvidia/5090-thermals.md](nvidia/5090-thermals.md). `Per Core` and `Per CCD` also exist; **start with `All Cores`** — a per-core matrix multiplies the validation work, and the all-core result is what tells you whether a per-core pass is even worth it. If it later needs splitting, `Per CCD` is the natural next step on this chip, because the two dies are not alike: CCD0 carries the 3D V-Cache and clocks lower, CCD1 does not and boosts higher (~5 385 MHz observed single-thread).

    **⚠️ Negative CO fails at IDLE, not under load.** The failure mode is a single core boosting to max frequency at light load, where the reduced voltage no longer holds — so an all-core stress test that passes proves almost nothing about CO. That is why step 4 of the test suite (full-day idle soak) is not optional padding; it is the test that actually targets this. Symptom is typically a spontaneous reboot or a WHEA/Cache Hierarchy entry in `ras-mc-ctl --errors` while the machine is doing nothing.

  - **Leave these alone in the same menu** (all confirmed present on-screen 2026-08-04): `PBO Limits` = `Auto`, `Precision Boost Overdrive Scalar Ctrl` = `Auto` (scalar raises sustained voltage — it pulls against undervolting), `CPU Boost Clock Override` = `Disabled` (adds a second instability variable on top of CO), `Platform Thermal Throttle Ctrl` = `Auto`.
  - **`GFX Curve Optimizer` — do not touch.** Separate submenu with its own Sign/Magnitude, and it governs the **integrated Radeon graphics**, a different voltage domain from the CPU cores. The iGPU is unused here (RTX 5090 drives the displays; see [hardware/hide-amd-apu.md](hardware/hide-amd-apu.md)), so there is nothing to gain and one more variable to debug. Leave Sign/Magnitude at `Positive`/`0`.
  - **`Curve Shaper` — leave everything `Auto` for now.** Zen 5 feature: a grid of offsets per frequency band × temperature band (`Min/Low/Med/… Frequency` × `Low/Med/High Temperature`, all `Auto` as of 2026-08-04). It exists precisely to fix the idle-instability problem above — it can apply a gentler offset in the low-frequency/low-temperature cells where negative CO bites. **That makes it the right tool if −15 all-core turns out to be idle-unstable but stable under load**: relax the low-frequency/low-temperature cells rather than backing the whole curve off. Do not open it on the first pass — it is a 9+ cell matrix and there is no baseline yet to judge it against.
  - ✅ **ECO Mode — 105 W applied 2026-08-04.** Superseded warning, kept for the lesson: the ASUS 800-series manual documents only a **65 W** tier, and the real board offers 105 W. A generic cross-board manual under-reports what a specific board exposes — check the screen. The fallback below was therefore never needed. **Had 105 W been absent, do not take 65 W as a substitute** — that is a far deeper cut than planned (65 W TDP ≈ 88 W PPT vs 105 W TDP ≈ 142 W, against a 230 W stock PPT) and would cost well more than the ~5% the plan is built around. Instead set the 105 W equivalent manually: `Precision Boost Overdrive → PBO Limits → Manual` with **PPT = 142 W** (leave TDC/EDC auto unless they block it). Check on-screen first — the manual is a generic cross-board 800-series doc, so this board may still expose 105 W.
  **Sequencing (operator decisions 2026-08-03): proceed now rather than waiting for board clearance, and set EXPO + ECO + CO in ONE BIOS visit.** Basis: ~a week without random reboots as the baseline, and `rasdaemon` now running to catch corrected errors persistently.
  **Attribution comes from the TEST SUITE, not from staging the changes** — each test isolates one variable, so one visit is fine provided the suite actually gets run, in this order:
  1. **Memtest86+ ≥4 passes** → isolates EXPO/RAM. Passing clears the memory path.
  2. **Per-core CO validation — READY, run all three detectors (operator decision 2026-08-04).** Isolates CO: instability is **core-specific and reproducible**, board damage is not, so a single failing core means that core's offset rather than the board.

     **Why this is a deliberate test and not a waiting game.** Negative CO does not fail "at idle" in the literal sense; it fails where voltage is lowest *relative to the demanded frequency* — one or two cores boosting to ~5.4 GHz while the rest sleep. `taskset`-pinning one thread to one core recreates exactly that, so the crash lands in a window chosen on purpose instead of during work. That is the point of the per-core pass; thoroughness is secondary.

     **Three detectors, weakest → strongest. Run all three; a pass on a weak one is not evidence of a pass on a strong one.**

     | Tool | Package | Sensitivity to CO |
     |---|---|---|
     | `stress-ng --cpu 1 --cpu-method fft` | `stress-ng` (repo, **installed**) | weak — a pass is encouraging, not evidence |
     | `y-cruncher` | AUR `y-cruncher` (verified present 2026-08-04) | strong — different math paths |
     | `mprime` small-FFT | AUR `mprime` (verified present 2026-08-04, maint. graysky) | strongest for CO; SSE first, then AVX2 |

     Skeleton — one thread, one core, cycling:
     ```fish
     for c in (seq 0 31)
         echo "core $c"
         taskset -c $c stress-ng --cpu 1 --cpu-method fft -t 60
     end
     ```
     ~10 min/core for the `mprime` pass, so script it and run it overnight.

     **Start at CO −10, not −15.** Materially less likely to be unstable, still worth real voltage at the boost point, and one extra BIOS trip is cheaper than a crash during work. Step to −15 after a clean pass.

     **Read the early-warning channel after every stage:** `sudo ras-mc-ctl --errors`. CO instability often throws a corrected **Cache Hierarchy** error *before* it crashes — back off 5 on that core even without a crash. ⚠️ The MCE at **2026-08-04 09:36:00** is the synthetic injection; anything after it is real.

     **Recovery if a setting will not POST:** rear-IO **CMOS clear button** (section A).

     **Done when:** all 32 logical cores pass all three detectors at the chosen offset, plus the idle soak below. **Honest limit:** no test proves stability — it moves discovery earlier.
  3. **`y-cruncher`** component tests → different math paths, catches what mprime misses.
  4. **Idle soak, a full day** → CO fails at idle/light load, not only under stress. Watch `ras-mc-ctl --errors`: corrected Cache Hierarchy errors = back off 5 on that core even without a crash.
  **CPU power policy — decided 2026-08-03: leave CachyOS defaults alone, GNOME power mode = *Balanced*, done.** One knob: **BIOS ECO mode is the only power-envelope control**. Balanced gives `powersave` + `EPP=balance_performance`; full boost under load (the hardware decides via CPPC either way), lower idle clocks, and no measurable difference in sustained all-core work — where ECO binds anyway. **The only hard requirement: do not change the power mode between the before and after benchmark runs**, or the comparison measures the profile instead of ECO/CO. Set on this machine via `Settings → Power → Power Mode` (or the top-right quick-settings menu); verify with `powerprofilesctl get`.
  How it actually works here, since this caused confusion: CachyOS ships **no** governor/EPP policy — nothing in `/etc` or `/usr/lib` sets either. The driver is `amd-pstate-epp`, so the *hardware* picks frequencies via CPPC and the governor is only a bias hint (on this driver `powersave` is the normal operating mode, **not** a slow one). The thing that actually sets it is **GNOME's power mode via `power-profiles-daemon`** — D-Bus-activated, which is why `systemctl is-enabled` reports it disabled while `powerprofilesctl get` answers. An earlier reading of `EPP=power` was just GNOME on *Power Saver*.
  **Do NOT enable `cpupower.service`** — GNOME already persists this across reboots; a second writer on the same knob is how the two silently disagree. Requirement for the benchmark is only that the power mode is **identical in the before and after runs**; leaving it on Performance satisfies that with no extra machinery.
  **⚠️ The one thing that cannot be recovered later: the stock baseline benchmarks.** Run them BEFORE touching anything (protocol in the 9950X3D item above) — once ECO/CO are set, the stock numbers are gone unless everything is undone to retake them. ECO cannot cause instability (it is a lower power ceiling, if anything it *improves* margin), so combining it with CO is not the risk; skipping the baseline is.
  **First CO setting: all-core −15, not per-core −25.** One dial to back off if unstable; refine per-core later once it has proven itself. Do NOT touch voltages or C-states (auto is right). CO instability and latent board damage present identically (random reboots, corrected MCEs). The full CO/ECO plan — including the stability regimen and the before/after benchmark protocol — is the 9950X3D item above, and it starts *after* clearance. Note: **CO and ECO are BIOS-only on this platform**; `ryzen_smu`, `corectrl` and `zenstates` are all absent here and per-core CO offsets are not reliably settable from Linux userspace on Zen 5 desktop. Linux does the *measurement* half (`turbostat`, `mprime`/`y-cruncher`, `ras-mc-ctl`), BIOS does the setting.
- ✅ **Desktop — RGB outage RESOLVED 2026-08-04: BIOS `LED lighting` was `Aura Off`.** Full mechanism in [nvidia/openrgb.md](nvidia/openrgb.md). **Retracted:** the OpenRGB `1.0rc2→rc3` regression theory and its planned pacman-cache downgrade test — there was never an OpenRGB fault, and the "writes accepted, nothing visible" symptom that made rc3 look guilty was the hardware gate. Do not re-run that test. Software side was correct throughout: `openrgb 1.0rc3`, `~/.config/autostart/openrgb-apply-profile.desktop` present and enabled, byte-identical to its dotfiles source. **Remaining, small:**
  - Re-test whether plain `openrgb -p` applies or whether `--server` is required — see the open question in [nvidia/openrgb.md](nvidia/openrgb.md); this was untestable while the lights were gated. Update the dotfiles `Exec=` line only if the test says so.
  - Save an OpenRGB profile with the desired RAM/GPU colours — currently runtime-only, so it does not survive a reboot.
  - Delete `~/.config/autostart/openrgb-apply-profile.desktop.bak`, a redundant identical copy.
- Use Limine bootloader on the laptop (automatic snapshots supported).
- Compare Brave Wayland flags to standard values; possibly remove some.
- **Desktop:** confirm the PowerMizer max-perf autostart is removed and PowerMizer is back to default (`nvidia-settings -q [gpu:0]/GpuPowerMizerMode`).
- **Desktop:** enlarge the `/boot` partition so more Limine snapshots fit — see [recovery/boot-part-enlarge.md](recovery/boot-part-enlarge.md).
- **Desktop:** verify + remove the now-unneeded GNOME screencast workaround — the VA-API blocklist autostart (`~/.config/autostart/gnome-screencast-vaapi-blocklist.desktop`) **and** the `GST_PLUGIN_FEATURE_RANK` line in `/etc/environment` (recording works fine without them on the laptop; test the recorder on the desktop, then delete both).
- Room correction for the desktop hi-fi chain (PC → mobo optical → WiiM Vibelink). Blocked on hardware: needs a **calibrated** measurement mic (miniDSP UMIK-1, ~€100, ships with a per-unit calibration file) — a phone mic or the Razer Seiren is uncalibrated and rolls off in the bass, i.e. exactly where correction is the only thing that reliably works. Toolchain is verified present: `paru -S roomeqwizard` (REW, needs Java — installed), and PipeWire 1.6.8 has `param_eq` (reads REW's APO export via `filename`), `convolver` (FIR/impulse response), and the `bq_*` biquads builtin in `libspa-filter-graph-plugin-builtin.so` — no extra plugins. **Correct only below ~300 Hz:** room modes are minimum-phase, so minimum-phase biquads fix magnitude and phase together; above the Schroeder frequency you'd be EQ'ing reflections into the direct sound. Write it up as `audio/room-correction.md` (next to `noise-suppression.md` — same PipeWire filter-chain category) once it's measured and working. Note when it lands: correction breaks the bit-perfect path documented in [audio/sample-rates.md](audio/sample-rates.md) by design — that is the point at which >16-bit output starts to matter, and the bit-compare test is worth re-running to see exactly what changed.
  Two checks that belong in the run, both cheap and both invalidating if skipped:
  - **Before measuring:** confirm the Vibelink is not applying EQ/tone/room DSP of its own to the **optical** input (WiiM Home app). Unknown as of 2026-08-03. A curve measured through an unknown downstream EQ corrects the wrong system, and two EQs stacked silently is unfalsifiable by ear.
  - **After inserting the filter sink:** confirm rate-following survives it — an EQ sink that pins the graph to 48 kHz quietly re-introduces the 44.1 → 48 resample that `99-clock-rates.conf` exists to remove. Play a 16/44.1 source through the EQ sink, then `pw-metadata -n settings | grep clock.rate` and `cat /proc/asound/card2/pcm*p/sub0/hw_params`. If it does pin: correction still wins that trade, but record it as a made decision in `audio/sample-rates.md`, not a surprise.
- **Desktop — experiment, unproven:** upsample 44.1 → 88.2 on the PC (soxr; `ffmpeg` here is built `--enable-libsoxr`, `mpv` not installed) to relax the Vibelink's **fixed** ES9039Q2M reconstruction filter — linear phase fast roll-off, not user-selectable, confirmed by WiiM Oct 2025. At 44.1 the filter works in a 20–22.05 kHz window; at 88.2 it gets 20–44.1 kHz, so its pre-ringing moves out of reach. 176.4 is not an option — the ALC1220P does not offer it. Pre-ringing audibility is genuinely contested; this is a free A/B, not a known win.
- **Laptop — TRIAL:** Apple Music lossless via Waydroid. Native Linux caps at high-bitrate AAC (Cider/Sidra/web — FairPlay withholds ALAC from MusicKit); the Android app in Waydroid is the only proven Linux software path — 24-bit/48 kHz, the standard-lossless tier ([confirmed setup walkthrough](https://ivonblog.com/en-us/posts/play-apple-music-android-on-linux/)); Hi-Res 96/192 is architecturally out (Waydroid resamples to 48 kHz at the Linux boundary). Wine can't (no WebView2/DRM path); Windows VM rejected (operator).
  History: an earlier Waydroid install on this laptop broke host stuff randomly (file manager among it; symptoms not recorded). Both known breakage classes have root-cause fixes below — applied **before** first launch, not reactively. Preflight verified on lappy 2026-07-26: kernel `7.1.4-1-cachyos` (binder built-in — all CachyOS kernels except hardened; `grep -i binder /proc/filesystems` → present), IPv6 on (Waydroid needs it), nftables/Docker services inactive (their conflict class absent), `waydroid 1.6.3` in extra repo, not currently installed. **ufw is the active firewall → prime suspect for the old breakage** (default deny on forwarded traffic vs Waydroid's inserted rules). Desktop: unverified, re-run preflight there before trying.
  1. Snapshot infra FIRST — **auto-snapshots are NOT active on lappy** (verified 2026-07-26: `snapper` + `btrfs-assistant` installed, but `snap-pac` missing and `snapper-timeline`/`snapper-cleanup` timers disabled → pacman transactions snapshot nothing). Fix is independent of this trial and worth doing regardless:
     ```sh
     sudo pacman -S snap-pac                          # pre/post snapshot around every pacman run
     sudo systemctl enable --now snapper-cleanup.timer # prune the set
     ```
     Confirm a `root` config exists first: `sudo snapper list-configs` (if absent: `sudo snapper -c root create-config /`). Timeline timer left off deliberately — transaction snapshots are the ones that matter here. Rollback comfort: check the bootloader — if limine, `limine-snapper-sync` (not installed as of 2026-07-26) is what puts snapshots in the boot menu; without it rollback is manual via `btrfs-assistant`/`snapper undochange`, still fine for this trial.
  2. Install + init (GAPPS variant — Apple Music comes via Play Store). With snap-pac in place the pacman run snapshots itself; `waydroid init` writes only to `/var/lib/waydroid`:
     ```sh
     sudo pacman -S waydroid && sudo waydroid init -s GAPPS   # image download ~1 GB
     ```
  3. ufw accommodation BEFORE first container start:
     ```sh
     sudo ufw allow in on waydroid0 to any port 53
     sudo ufw allow in on waydroid0 to any port 67 proto udp
     sudo ufw route allow in on waydroid0 && sudo ufw route allow out on waydroid0
     ```
  4. Start + verdict: `sudo systemctl enable --now waydroid-container; waydroid session start`, then `waydroid status` must show a real IP (`UNKNOWN` = the known CachyOS failure shape, [forum thread](https://discuss.cachyos.org/t/internet-not-working-on-waydroid/26994) — their fix is firewalld-flavored, ufw equivalent is step 3). Immediately regression-check the old symptoms: file manager, DNS, VPN.
  5. Apple Music layer per the ivonblog guide: Google device registration (Play certification), Play Store → Apple Music, Magisk module to hide root (app refuses rooted-looking devices), PipeWire allowed-rates already widened — [audio/sample-rates.md](audio/sample-rates.md).
  6. Seamless daily use (no second-system feel — Android stays invisible):
     ```sh
     waydroid prop set persist.waydroid.multi_windows true   # apps open as normal desktop windows
     ```
     Play-Store installs auto-generate `.desktop` launchers → "Apple Music" appears in the app launcher, pinnable like a native app. Session must run for instant launch: autostart `waydroid session start` at login (user systemd unit or XDG autostart); cold start otherwise adds ~10–20 s on first click. Known seams, acceptable: Android UI conventions inside the window, clipboard mostly-works, media keys via MPRIS usually work.
  7. **Acceptance = soak, not smoke test** (operator bar: works resident all the time, or not at all): container + session stay resident through normal daily use incl. ≥1 reboot and ≥1 system update; seamless-launch behavior (step 6) is part of what the soak judges. Any random host breakage → snapshot rollback, trial CLOSED as failed, fall back is hardware (used iPhone/iPad + Lysoniq ~€12 + USB DAC — bit-perfect to 24/192, beats Waydroid's ceiling anyway).
  If Docker ever gets activated on this machine while the trial runs: add `"ip-forward-no-drop": true` to `/etc/docker/daemon.json` first (Arch Wiki Waydroid — Docker's FORWARD DROP breaks Waydroid networking).
