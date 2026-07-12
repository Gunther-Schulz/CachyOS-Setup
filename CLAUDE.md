# CachyOS-Setup — doc maintenance guide

Read before editing docs in this repo. (Global working rules live in
`~/.claude/CLAUDE.md`; this file is repo-specific.)

## Clean-state principle

A doc describes each machine's **current applied state + why** — a setup
reference, not a lab notebook of everything tried.

**Keep**
- The applied fix/config (exact commands + paths) and a one-paragraph **why**
  it's needed — the reasoning that makes the setting trustworthy and re-derivable.
- Operational bits: how to verify, how to undo, tradeoffs.
- Load-bearing safety notes: "don't re-add X", "don't re-try Y", the sign that
  tells bug A from bug B.

**Cut** — and just remove it, no "considered/rejected" tombstone:
- Old/superseded states, ruled-out investigations (the journey), dated
  blow-by-blow narrative, verbose log dumps / backtraces, "tried N versions".
- Redundant CachyOS/kernel defaults — if the default already does it, don't
  prescribe it.
- Dormant "not-applied" items — a workaround for a problem that isn't happening.
- A ruled-out cause is worth **one line at most**, and only if it carries a
  safety signal (don't re-try / don't re-add).

## Verify before documenting

Confirm a setting is actually applied against the live system before writing it
as fact — `sysctl`, `pacman -Q`, `ls /etc/…`, `systemctl is-enabled`. Facts come
from the machine, not memory. Desktop-only items can't be verified while the
desktop is down — mark them, don't guess.

## Conventions

- **Machine tag** at the top of each doc: `**Machine:** Laptop | Desktop | Both`;
  untagged = both.
- **Cross-link, don't duplicate:** if a real artifact exists (script, config,
  hook — e.g. in the dotfiles repo), link to it instead of pasting a copy.
- Terse over verbose; commands in fenced blocks; one canonical home per fact.
