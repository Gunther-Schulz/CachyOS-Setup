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
  ✅ **Parsing verified against the first real run (2026-08-04)** — and it caught a bug, which is the point of checking. The bogo-ops extraction was correct; **`PkgWatt` came out `n/a`** because `turbostat --out` writes an elapsed-time line (`60.014170 sec`) *before* the column header, and the parser only looked at line 1. Fixed: the header is now found wherever it sits. Re-parsing the **saved** stock turbostat logs with the fixed code recovered the numbers, so no re-run was needed. Also changed: `CoreTmp` → **`PkgTmp`** (the `-S` summary row carries the package sensor; `CoreTmp` silently produced no column), and `Bzy_MHz` + `PkgTmp` now land in `summary.txt` alongside watts.

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
- **Desktop — PARKED: fans surge up and down under light load. Do NOT blame ECO mode, and do not tune this in the BIOS.** Observed after ECO 105 W was applied (2026-08-04): the surging is unchanged from before, which is expected — **ECO caps *sustained all-core* power; the surging is driven by *single-core boost transients*, which ECO does not touch.** Reverting ECO would cost the efficiency and fix nothing acoustically. Mechanism, measured on this machine 2026-08-04 at loadavg 1.7: `k10temp` reports **Tctl 71.8 °C while the actual dies sit at CCD1 49.5 °C / CCD2 72.4 °C** — Tctl is a deliberately fast-moving control value, and it is what a motherboard fan curve follows, so any brief boost yields an instant fan ramp. **Fix belongs in user space, not Q-Fan** (operator preference, and the pre-existing plan): `coolercontrol 4.3.1-2` is installed and `fan-control/` already holds the scripts and channel labels. What to configure there: a response delay / hysteresis on the CPU channel plus a speed floor so it does not fully drop and re-surge, and consider driving the curve from a **CCD** sensor rather than Tctl. **Blocked until** the thermal envelope is final — curves tuned against pre-CO, pre-GPU-undervolt heat output all have to be redone; see the sequencing note in the GPU item above. **Unverified:** the ASUS Q-Fan submenu labels were never checked against the manual — irrelevant if this stays in user space.
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

- **Desktop — READY: GPU stress test, to be run alongside `nvidia-gpu-sensors --watch`.** The point is not "does it crash" but capturing **hotspot-minus-edge under sustained load** — the delta that reveals a bad mount or dried thermal pads, and which idles at 8 °C on this card. Two load types, both needed, because they stress different things:

  | Tool | Install | Run | What it loads |
  |---|---|---|---|
  | `gpu-burn` | AUR `gpu-burn-git` | `./gpu_burn 600` | cuBLAS compute power-virus — highest sustained power draw |
  | FurMark 2 | AUR `furmark` | GUI / OpenGL + Vulkan stress | graphical power-virus, exercises the render path |
  | Unigine Superposition | AUR `unigine-superposition` | GUI benchmark | realistic game-like load, closest to actual use |

  Protocol — three terminals, load running ≥10 minutes so the heatsink actually reaches steady state (the first 2–3 minutes tell you nothing):
  ```fish
  sudo ~/dev/vendor/nvidia-gpu-sensors/build/nvidia-gpu-sensors --watch
  nvidia-smi dmon -s pucvmet -o DT -f ~/bench/gpu-stock.csv
  ./gpu_burn 900     # or FurMark / Superposition
  ```
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

  **Next evidence to collect** (unchanged in kind, now much better targeted): `journalctl -k -b -1 -e` after the next freeze, grepping for `Xid` — an Xid number names the failure class directly. `tools/gpu-hang-watch.sh` already exists but was written for Marvel Rivals specifically, so its watch is narrower than "any GPU-load freeze"; widen it before relying on it.

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

     ❌ **The userspace `mce-inject` tool is NOT packaged for Arch — not in the repos, not in the AUR** (`yay -S mce-inject` → "No AUR package found"). An earlier note here called it "AUR-only"; that was inferred from `pacman -Qo` returning no owner, which only proves it is not installed. Upstream is [`andikleen/mce-inject`](https://github.com/andikleen/mce-inject), buildable from source.

     **Try the kernel interfaces first — they need no userspace tool:**
     ```fish
     sudo modprobe einj;       ls /sys/firmware/acpi/einj        # cleanest if the BIOS exposes EINJ
     sudo modprobe mce-inject; ls /sys/kernel/debug/mce-inject/ /sys/kernel/debug/mce/
     ```
     EINJ needs firmware tables that consumer boards frequently omit, so it may simply not appear. Whichever interface materialises, read its actual file list before writing to it — the field layout differs between them and is not worth reconstructing from memory.

     ⚠️ **Corrected (CE) errors only.** An uncorrected/fatal status word panics the machine by design — that is the tool working as intended, not a mistake to discover experimentally.

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

    Magnitude is in counts of roughly 3–5 mV, so −15 ≈ −45…−75 mV. `Per Core` and `Per CCD` also exist; **start with `All Cores`** — a per-core matrix multiplies the validation work, and the all-core result is what tells you whether a per-core pass is even worth it. If it later needs splitting, `Per CCD` is the natural next step on this chip, because the two dies are not alike: CCD0 carries the 3D V-Cache and clocks lower, CCD1 does not and boosts higher (~5 385 MHz observed single-thread).

    **⚠️ Negative CO fails at IDLE, not under load.** The failure mode is a single core boosting to max frequency at light load, where the reduced voltage no longer holds — so an all-core stress test that passes proves almost nothing about CO. That is why step 4 of the test suite (full-day idle soak) is not optional padding; it is the test that actually targets this. Symptom is typically a spontaneous reboot or a WHEA/Cache Hierarchy entry in `ras-mc-ctl --errors` while the machine is doing nothing.

  - **Leave these alone in the same menu** (all confirmed present on-screen 2026-08-04): `PBO Limits` = `Auto`, `Precision Boost Overdrive Scalar Ctrl` = `Auto` (scalar raises sustained voltage — it pulls against undervolting), `CPU Boost Clock Override` = `Disabled` (adds a second instability variable on top of CO), `Platform Thermal Throttle Ctrl` = `Auto`.
  - **`GFX Curve Optimizer` — do not touch.** Separate submenu with its own Sign/Magnitude, and it governs the **integrated Radeon graphics**, a different voltage domain from the CPU cores. The iGPU is unused here (RTX 5090 drives the displays; see [hardware/hide-amd-apu.md](hardware/hide-amd-apu.md)), so there is nothing to gain and one more variable to debug. Leave Sign/Magnitude at `Positive`/`0`.
  - **`Curve Shaper` — leave everything `Auto` for now.** Zen 5 feature: a grid of offsets per frequency band × temperature band (`Min/Low/Med/… Frequency` × `Low/Med/High Temperature`, all `Auto` as of 2026-08-04). It exists precisely to fix the idle-instability problem above — it can apply a gentler offset in the low-frequency/low-temperature cells where negative CO bites. **That makes it the right tool if −15 all-core turns out to be idle-unstable but stable under load**: relax the low-frequency/low-temperature cells rather than backing the whole curve off. Do not open it on the first pass — it is a 9+ cell matrix and there is no baseline yet to judge it against.
  - ✅ **ECO Mode — 105 W applied 2026-08-04.** Superseded warning, kept for the lesson: the ASUS 800-series manual documents only a **65 W** tier, and the real board offers 105 W. A generic cross-board manual under-reports what a specific board exposes — check the screen. The fallback below was therefore never needed. **Had 105 W been absent, do not take 65 W as a substitute** — that is a far deeper cut than planned (65 W TDP ≈ 88 W PPT vs 105 W TDP ≈ 142 W, against a 230 W stock PPT) and would cost well more than the ~5% the plan is built around. Instead set the 105 W equivalent manually: `Precision Boost Overdrive → PBO Limits → Manual` with **PPT = 142 W** (leave TDC/EDC auto unless they block it). Check on-screen first — the manual is a generic cross-board 800-series doc, so this board may still expose 105 W.
  **Sequencing (operator decisions 2026-08-03): proceed now rather than waiting for board clearance, and set EXPO + ECO + CO in ONE BIOS visit.** Basis: ~a week without random reboots as the baseline, and `rasdaemon` now running to catch corrected errors persistently.
  **Attribution comes from the TEST SUITE, not from staging the changes** — each test isolates one variable, so one visit is fine provided the suite actually gets run, in this order:
  1. **Memtest86+ ≥4 passes** → isolates EXPO/RAM. Passing clears the memory path.
  2. **Per-core `mprime`** (`taskset -c N`, SSE first then AVX2, ~10 min/core, scripted overnight) → isolates CO. CO instability is **core-specific and reproducible**; board damage is not. A single failing core = that core's offset, not the board.
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
