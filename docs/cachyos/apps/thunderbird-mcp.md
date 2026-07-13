# Thunderbird/Betterbird MCP

Gives an MCP client (Claude Code / Claude Desktop) access to the local mail
client — search mail, compose, manage filters/folders, contacts, calendar.

Mail client here is **Betterbird** (`betterbird-bin`), which uses the Thunderbird
profile dir `~/.thunderbird/`, so the Thunderbird extension works unchanged.

## Our fork

We run a **fork** of [TKasperczyk/thunderbird-mcp](https://github.com/TKasperczyk/thunderbird-mcp):
[Gunther-Schulz/thunderbird-mcp](https://github.com/Gunther-Schulz/thunderbird-mcp),
cloned at `~/dev/Gunther-Schulz/thunderbird-mcp`. Clone + MCP registration are
done by dotfiles `claude/install.sh` §9 (which also adds an `upstream` remote for
rebasing) — that script is the reproducible source of truth, not `~/.claude.json`.

**Why the fork:** one commit adds a **`saveMessage`** bridge tool — writes a
message's full `.eml` and/or its attachments to a caller-chosen path (reuses
`getMessage` under the hood). It's a **bridge-only** change (`mcp-bridge.cjs`),
so no `.xpi` rebuild is needed — the stock extension still works. Rebase on
upstream to pull new features; the single `saveMessage` commit replays on top.

## Two moving parts

1. **Extension** (`.xpi`) inside Betterbird — the HTTP server that talks to mail.
   Installed in the profile: `~/.thunderbird/<profile>/extensions/thunderbird-mcp@tkasperczyk.dev.xpi`.
   Auto-updates from v0.7.3 on (Betterbird ships `xpinstall.signatures.required=false`).
2. **Bridge** (`mcp-bridge.cjs`) — stdio↔HTTP shim the MCP client spawns.

The bridge auto-discovers the server's port + bearer token from
`<tmp>/thunderbird-mcp/connection.json` (localhost only, dynamic port 8765–8774).
**Betterbird must be running** for tools to actually reach mail.

## Wiring (Claude Code)

Registered in `~/.claude.json` as `thunderbird-mail` → must point at the **fork's**
bridge:
```json
"thunderbird-mail": {
  "type": "stdio",
  "command": "node",
  "args": ["/home/g/dev/Gunther-Schulz/thunderbird-mcp/mcp-bridge.cjs"]
}
```
Verify: `claude mcp list` → `thunderbird-mail … ✔`.

⚠️ **Gotcha (hit 2026-07):** the registration pointed at a non-existent upstream
path (`.../TKasperczyk/thunderbird-mcp/...`) → `claude mcp list` showed *Failed to
connect*. The bridge lives only in **our fork dir**. If it fails to connect,
check the path first, then that Betterbird is running.

## Verify / debug the bridge directly

```bash
cd ~/dev/Gunther-Schulz/thunderbird-mcp
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node mcp-bridge.cjs   # lists tools (incl. saveMessage)
```
`tools/list` responds even with Betterbird closed (static list); actual mail
calls need Betterbird open.
