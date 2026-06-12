# ASUS Laptop (ROG / TUF)

`yay -S asusctl rog-control-center` for features control.

**Suspend / GPU MUX:** see [gpu-mux-suspend.md](gpu-mux-suspend.md) — the FA607PV must be in Hybrid GPU mode or s2idle suspend hangs.

**Keyboard flashing during sleep:** that's the Aura *sleep animation* (`sleep: true` in `/etc/asusd/aura_tuf.ron`) — cosmetic, not an error. The machine genuinely sleeps/wakes; modern-standby (s2idle) keeps the EC powered so the keyboard can animate. Turn it off with:
```sh
asusctl aura power-tuf --sleep false      # also: --boot / --awake / --shutdown <true|false>
```

**Display switching (external monitor):** see [display-switching.md](display-switching.md).
