# Claude Desktop (unofficial, Linux)

Anthropic's Claude Desktop app is **not** officially on Linux. These are community packages by **patrickjaja** that repackage the official binary and add a native Cowork backend. For the terminal CLI see [Claude Code](claude-code.md) — different cockpit, same engine.

## Installation

AUR (via `paru`/`yay`):

```bash
paru -S claude-desktop-bin claude-cowork-service
```

- **`claude-desktop-bin`** — the Electron app, repackaged from the official Windows binary (runs `--no-sandbox`). Provides `claude-desktop`. Deps: `alsa-lib gtk3 nss`.
- **`claude-cowork-service`** — "native Linux backend" for Cowork (Go, MIT), reverse-engineered from the Windows `cowork-svc.exe`. Runs as a systemd **user** service.
- Useful optional deps it suggests: `claude-code` (the agent runtime Cowork drives), plus Computer-Use tooling — `xdotool`/`ydotool` (input), `grim`/`scrot` (screenshots), `wmctrl`, `jq`.

The Cowork backend is a user unit (enabled by default):

```bash
systemctl --user enable --now claude-cowork
```

## Cowork: native vs KVM backend

The backend has **two modes**, selected by the `COWORK_VM_BACKEND` env var:

| Mode | What it does |
|------|--------------|
| **`native`** (default) | Runs Claude Code **directly on the host** — no VM. Code/shell has full host access; the official VM safety model does **not** apply. |
| **`kvm`** | Runs each Cowork session in a real **QEMU/KVM VM** (the same Anthropic guest image used on macOS/Windows), `$HOME` shared via virtiofs, control over AF_VSOCK. Genuine isolation parity with a Windows client. |

On macOS/Windows the sandbox is mandatory; on this Linux port it's **opt-in**. In `native` mode the agent's code runs unsandboxed on your real machine — fine if you trust it, but know that's what's happening.

## Enabling KVM mode 🧪

**Prereqs** (all in the repos): `/dev/kvm` accessible, the `vhost_vsock` module, and a QEMU/virtiofsd/OVMF stack:

```bash
paru -S qemu-base qemu-img virtiofsd edk2-ovmf   # qemu-desktop also fine
```

The VM bundle (kernel + initrd + 8 GB rootfs) is auto-downloaded by Claude Desktop to `~/.config/Claude/vm_bundles/`.

1. **Load `vhost_vsock` and persist it:**

```bash
sudo modprobe vhost_vsock
echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf
```

2. **Point the service at the KVM backend** (drop-in for the user unit):

```bash
systemctl --user edit claude-cowork
# add, in the [Service] section:
#   Environment=COWORK_VM_BACKEND=kvm
systemctl --user daemon-reload
systemctl --user restart claude-cowork
```

3. **Verify it came up on KVM, not native:**

```bash
journalctl --user -u claude-cowork | grep 'starting ('
#   want: cowork-svc-linux X.Y.Z starting (kvm backend)
```

When a session starts you'll see a real `qemu-system-x86_64` (`-enable-kvm`, `vhost-vsock-pci`, `virtiofsd`); the first run converts the 8 GB `rootfs.vhdx` → a qcow2 overlay (slow + several GB).

## Gotchas (learned the hard way)

- **`vhost_vsock` "module not found" right after a kernel update → reboot.** If you bumped `linux-cachyos` but haven't rebooted, the *running* kernel's module tree is already gone, so `modprobe vhost_vsock` fails with `not found in directory /lib/modules/<running-version>`. It's not missing — it's a wrong-kernel mismatch. Reboot into the new kernel; the `modules-load.d` entry then auto-loads it. (`vhost_vsock` is `=m` on CachyOS, not built-in.)

- **Don't switch backends mid-session.** Flipping `native → kvm` while a Cowork chat is live — or resuming an old chat into KVM — breaks the guest's API access with `API Error: … Self-signed certificate detected`. KVM routes the guest's API calls through the app's **MITM proxy** (so your OAuth token never enters the VM), and the proxy's CA only provisions correctly on a **clean session start**. Fix: after enabling KVM, start a **brand-new** Cowork chat — don't migrate an existing one.

- **The app may need a relaunch to pick up KVM.** KVM listens on a different socket (`cowork-kvm-service.sock` vs `cowork-vm-service.sock`); the desktop app auto-detects which is present *at launch*. If it was running when you switched, quit and reopen it.

- **Folders are per-conversation; cloud folders may not mount.** A new Cowork chat starts with none of your folders attached — connect the folder (or make a Project) each time. Folders on OneDrive/SharePoint/network drives can refuse to mount into the VM (`cannot be mounted. Request a project or document folder instead`); use a real local folder.

- **GUI death (app *or* GNOME crash) orphans the guest process → `already running` on reopen.** `claude-cowork` is a `systemd --user` service with no `BindsTo`/`PartOf` the graphical session, so it — and its child QEMU VM — survive anything that only kills the GUI: the app crashing, *or a GNOME/Wayland compositor crash that takes the app down with it*. The session's guest process keeps running, so reopening the conversation fails with `guest spawn failed: … process with name "<session-slug>" already running`. Fix: restart the service — `systemctl --user restart claude-cowork` — which tears down the VM + the ghost. Conversation + connected-folder files persist; only the VM runtime is lost, so the next message boots a fresh VM and resumes. **On the FA607PV this was often self-inflicted:** Claude Desktop's own Chromium GPU process was a *trigger* of the GNOME compositor crash — the [gfx11 iGPU GPU-reset bug](../laptop/amdgpu-gfx-ring-timeout.md) (`Process claude … SQC (data)` page fault → MODE2 reset → session dies). Fixed 2026-06-30 by moving compositing onto the NVIDIA dGPU.

## Verify the whole stack

```bash
pacman -Q claude-desktop-bin claude-cowork-service claude-code
systemctl --user is-active claude-cowork
lsmod | grep vhost_vsock
ls ~/.config/Claude/vm_bundles/claudevm.bundle/   # vmlinuz, initrd, rootfs.vhdx
```

## Upstream

- https://github.com/patrickjaja/claude-desktop-bin
- https://github.com/patrickjaja/claude-cowork-service
