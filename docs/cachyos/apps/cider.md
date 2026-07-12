# Apple Music with Cider

Third-party Apple Music client (Cider 4). Needs an active Apple Music
subscription **and** a one-time Cider license (~$4).

## Install — official Arch repo (auto-updates via pacman)

itch.io distribution is **deprecated** (as of Feb 2025). Don't download the
old `Cider-git-arch-x64.pacman` file anymore — use the repo instead.

Import + locally sign the repo key:

    curl -s https://repo.cider.sh/ARCH-GPG-KEY | sudo pacman-key --add -
    sudo pacman-key --lsign-key A0CD6B993438E22634450CDD2A236C3F42A61682

Add to `/etc/pacman.conf`:

    [cidercollective]
    SigLevel = Required TrustedOnly
    Server = https://repo.cider.sh/arch

Then: `sudo pacman -Sy && sudo pacman -S cider`

**Migrating from the old itch.io install?** That was the `cider-client`
package; the repo `cider` package conflicts with it — accept the removal
when prompted. If the install aborts with
`cider: /usr/bin/cider exists in filesystem`, that's a stray **untracked
symlink** left by the old install (`/usr/bin/cider → /opt/Cider/cider`,
owned by no package). Remove it and retry:

    sudo rm /usr/bin/cider
    sudo pacman -S cider

## Licensing / auth — Taproom account

Cider now verifies your purchase via a **Taproom** account
(<https://taproom.cider.sh>). Existing itch.io buyers link the purchase
there (Purchase Methods → itch.io) — **no re-buy**.

⚠️ **Auto-login is broken on Linux.** On first launch the browser opens and
itch.io/Taproom sign-in succeeds, but the app stays on "Welcome to Cider"
and never proceeds — the `localhost:10767` callback 404s
([Cider-2 #1152](https://github.com/ciderapp/Cider-2/issues/1152),
[#1174](https://github.com/ciderapp/Cider-2/issues/1174)).

**Workaround that works:** on the Welcome screen click **Enter Taproom Token
Manually**, then paste the license key from
<https://taproom.cider.sh/licenses>. (If pasting the license key fails,
fall back to the `CTP-AUTH` cookie value: browser F12 → Application →
Cookies → `taproom.cider.sh` → copy `CTP-AUTH`.)
