# Claude Code CLI

## Terminal

Use **Ghostty** — best terminal for Claude Code (fast, image paste support, Wayland native).

```bash
sudo pacman -S ghostty
```

### Nautilus integration (Open in Ghostty)

Ghostty 1.1.0+ has built-in Nautilus integration — just install the Python extension loader:

```bash
sudo pacman -S python-nautilus
nautilus -q
```

Right-click in Nautilus now shows "Open in Ghostty". The default "Open in Console" (KGX) entry stays — it's hardcoded by GNOME; use the Ghostty entry instead. `nautilus-open-any-terminal` is NOT needed.

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
