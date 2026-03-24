# Claude Code CLI

## Terminal

Use **Ghostty** — best terminal for Claude Code (fast, image paste support, Wayland native).

```bash
sudo pacman -S ghostty
```

### Nautilus integration (Open in Ghostty)

Ghostty 1.1.0+ has built-in Nautilus integration. Just install the Python extension loader:

```bash
sudo pacman -S python-nautilus
nautilus -q
```

Right-click in Nautilus will now show "Open in Ghostty".

**Note:** The default "Open in Console" (KGX) entry remains — it's hardcoded by GNOME. Use the Ghostty entry instead. `nautilus-open-any-terminal` is NOT needed.

### Image paste

Requires Ghostty (or Kitty/WezTerm) + `wl-clipboard`:

```bash
sudo pacman -S wl-clipboard
```

Copy an image to clipboard, then Ctrl+V in Claude Code to paste it.

KGX/GNOME Console does NOT support image paste — it will error with `g-io-error-quark (15): No compatible transfer format found`.

## Installation

```bash
npm install -g @anthropic-ai/claude-code
```

## Global permissions

The global settings file is at `~/.claude/settings.json`. These permissions allow Claude Code to use all built-in tools and common git/python commands without prompting.

### Apply permissions from terminal

```bash
cat > ~/.claude/settings.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Edit(*)",
      "Write(*)",
      "Glob(*)",
      "Grep(*)",
      "WebSearch(*)",
      "WebFetch(*)",
      "Skill(*)",
      "Agent(*)",
      "TaskCreate(*)",
      "TaskUpdate(*)",
      "TaskGet(*)",
      "TaskList(*)",
      "TaskOutput(*)",
      "TaskStop(*)",
      "AskUserQuestion(*)",
      "EnterPlanMode(*)",
      "ExitPlanMode(*)",
      "EnterWorktree(*)",
      "ExitWorktree(*)",
      "NotebookEdit(*)",
      "CronCreate(*)",
      "CronDelete(*)",
      "CronList(*)",
      "LSP(*)",
      "mcp__playwright__*"
    ],
    "defaultMode": "dontAsk"
  },
  "enabledPlugins": {
    "clangd-lsp@claude-plugins-official": true
  }
}
EOF
```

**What this does:**
- `Bash(*)` — all shell commands without prompting. Safe because `sudo` requires a password, and offsite backups protect against accidental data loss. All specific bash permissions (git, python, gh, etc.) are redundant with this and not needed.
- All built-in tools (Read, Edit, Write, Glob, Grep, etc.) — no prompts
- Playwright MCP tools for browser automation
- clangd LSP plugin for C/C++ intelligence
- `defaultMode: dontAsk` — auto-allow matching permissions without confirmation

### Per-project permissions

Additional project-specific permissions can be added in project `.claude/settings.json` files or via `/permissions` in a session.
