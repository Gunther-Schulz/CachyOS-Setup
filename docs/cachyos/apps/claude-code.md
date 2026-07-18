# Claude Code CLI

## Terminal

Use **Ghostty** — best terminal for Claude Code (fast, image paste support, Wayland native).

```bash
sudo pacman -S ghostty
```

### Nautilus integration (right-click → open terminal here)

Ghostty ships no Nautilus extension of its own — use `nautilus-open-any-terminal` (AUR, pulls `nautilus-python`):

```bash
yay -S nautilus-open-any-terminal
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal 'custom'
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal custom-local-command 'ghostty --working-directory=%s'
nautilus -q
```

**Why `custom` and not `terminal 'ghostty'`:** the extension's built-in Ghostty entry
(`/usr/share/nautilus-python/extensions/nautilus_open_any_terminal.py`) is declared as
`Terminal("Ghostty")` with no `workdir_arguments`, so it launches bare `ghostty` with zero CLI
args and passes the folder only as the subprocess cwd. Ghostty's `gtk-single-instance` defaults
to `detect`, which — with no CLI args — hands the launch to the already-running instance and
drops that cwd; the new window then inherits the last-focused window's directory
(`window-inherit-working-directory`, default true). Result: the menu opens the *previous*
directory. The `custom` command passes `--working-directory` explicitly, which fixes the
directory and also makes `detect` skip single-instance. Upstream omission, not a local misconfig.

Tradeoff: `custom` is labelled generically, so the menu entry reads **"Open in Terminal"**, not
"Open in Ghostty".

**Removing the old entry:** the stock "Open in Terminal" came from gnome-terminal's own hardcoded
extension (`/usr/lib/nautilus/extensions-4/libterminal-nautilus.so`) — no setting redirects it.
`sudo pacman -Rns gnome-terminal` (Required By: None) drops it. To keep the app instead, add
`NoExtract = usr/lib/nautilus/extensions-4/libterminal-nautilus.so` to `/etc/pacman.conf` and
delete the `.so`.

Don't bother with `~/.config/xdg-terminals.list` or
`org.gnome.desktop.default-applications.terminal` — nothing in this path reads them (that
gsettings key points at `xdg-terminal-exec`, which isn't installed).

### Image paste

Requires Ghostty (or Kitty/WezTerm) + `wl-clipboard`:

```bash
sudo pacman -S wl-clipboard
command -v wl-paste || echo "MISSING — install wl-clipboard"
```

Verify it's installed — paste fails silently if missing (drag-and-drop still works, masking the problem). Copy an image, then Ctrl+V in Claude Code to paste it. KGX/GNOME Console does NOT support image paste (`g-io-error-quark (15): No compatible transfer format found`).

## Installation

```bash
npm install -g @anthropic-ai/claude-code
```

## Global permissions

`~/.claude/settings.json` is a **symlink managed by dotfiles** — edit the tracked source, not the file in place: `~/dev/Gunther-Schulz/dotfiles/claude/settings.json` (deploy via `~/dev/Gunther-Schulz/dotfiles/install.sh`). It carries the permission allowlist, hooks, and enabled plugins.

**Why permissive:** broad `Bash` access is safe unattended because `sudo` still needs a password and offsite backups cover accidental data loss — which makes a hand-maintained per-command allowlist (git, python, gh, …) redundant.

Project-specific permissions go in a project's `.claude/settings.json`, or via `/permissions` in a session.
