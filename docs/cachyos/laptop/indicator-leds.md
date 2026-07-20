# Indicator LEDs (FA607PV)

**Machine:** Laptop

The four indicator LEDs above the keyboard, in a 2×2 block. ASUS does not publish
the legend for this chassis and the icons are near-illegible, so the mapping was
derived empirically.

| Position | Function | Status |
|----------|----------|--------|
| top-left | Power / sleep | Confirmed — slow pulse while suspended |
| top-right | Charge | Confirmed — steady with charger connected |
| bottom-left | **Drive activity** | Confirmed — tracks `nvme0n1` I/O exactly |
| bottom-right | unknown | Unmapped |

None of these are exposed to software — `/sys/class/leds` carries only
`asus::kbd_backlight`. They are driven directly by the EC, so there is no sysfs
handle and mapping has to be done by provoking a subsystem and watching.

## Fast steady blink on bottom-left after wake — normal

A *fast, perfectly regular* blink that starts a few minutes after resume and runs
for a long time is **`rclone-bisync-manager` working through a backlog**, not a
fault. Four of the six sync jobs in `~/.config/rclone-bisync-manager/config.yaml`
are scheduled `0 0 * * *`; with `run_missed_jobs: true`, suspending across
midnight means all four fire at wake. Each uses
`--compare size,modtime,checksum`, which reads every file to hash it — a
continuous read stream with **zero writes**, hence a metronomic rather than
bursty LED.

Confirm rather than guess:
```bash
# sustained read with no write => checksum pass, not a fault
a=$(awk '$3=="nvme0n1"{print $6}' /proc/diskstats); sleep 5
b=$(awk '$3=="nvme0n1"{print $6}' /proc/diskstats)
echo "read: $(( (b-a)*512/5/1048576 )) MB/s"

ps -eo pid,etime,pcpu,args | grep '[r]clone bisync'
tail -f ~/.local/state/rclone-bisync-manager/logs/rclone.log
```
It stops on its own when the queue drains. Don't kill a running bisync — an
interrupted run can leave lock state needing a `--resync`.

## Mapping method

Establish a quiet baseline **first**, then provoke one subsystem and watch. Without
the baseline the test is worthless: a burst test against an already-saturated LED
shows no change and reads as a false negative.

```bash
# drive activity — needs an idle disk to be meaningful
dd if=/dev/zero of=/tmp/iotest bs=1M count=400 oflag=direct; sync
dd if=/tmp/iotest of=/dev/null bs=1M iflag=direct; rm /tmp/iotest
```

Which hotkeys the chassis actually advertises (decode the `Asus WMI hotkeys`
`B: KEY=` bitmap from `/proc/bus/input/devices`; `KEY_RFKILL`, `KEY_MICMUTE`,
`KEY_WLAN` and `KEY_BLUETOOTH` are all present here). To see which physical key
emits what:
```bash
sudo pacman -S evtest
sudo evtest /dev/input/event18   # "Asus WMI hotkeys"
```

## bottom-right — ruled out so far

**Software rfkill does not drive it.** GNOME's airplane-mode toggle blocks both
radios (`rfkill list` → `Soft blocked: yes`) with no change to the LED — so don't
re-test via GNOME or `rfkill block`. If it is airplane-related at all it is wired
to the EC hotkey path only, which a software block never reaches. Untested:
`KEY_RFKILL` via the actual hotkey, and `KEY_MICMUTE`.
