# Mercurius — household wiki

[Compose](../../services/mercurius/docker-compose.yml) runs [SilverBullet](https://docs.silverbullet.md) (`mercurius`) on space-needle: plans, trips, places, projects and lists as plain markdown, editable from phone and laptop. Named for the Roman god of communication and the planet Mercury. Nothing from Plutus (the vault) goes in here. Plan and later work: [automation plans](../../automation/plans/mercurius.md). Deployed on space-needle 2026-10-25, syncing to Forgejo.

| Host path | Contents |
|---|---|
| `/mammoth/mercurius` | SilverBullet's data folder: server config, accounts, git deploy keys, and each space under `spaces/` |

SilverBullet runs as the folder's owner (littledog, from setup). Each space is a folder of markdown files with its own git repository; SilverBullet commits changes about 30 seconds after editing stops and pushes them to Forgejo.

## Access

- `https://mercurius.loft.hsimah.com`, through space-needle's Caddy. LAN only until Tailscale is on the phones; never on the tunnel. There is no plain-HTTP `.space-needle` route: the offline PWA needs HTTPS, and each space is bound to one hostname.
- One account each. Both get `write` on the household space. In SilverBullet, `write` includes authoring Space Lua that runs in the other person's browser, so only trusted people get it.
- `SB_SHELL_BACKEND=off` disables the server shell endpoint for every space. The `-slim` image has no Runtime API. The HTTP proxy (`net.proxyFetch`) remains: a `write` member can fetch URLs from the server's network.

## Setup

1. Copy [.env.example](../../services/mercurius/.env.example). `sudo bash setup.sh` creates `/mammoth/mercurius` owned by littledog; then `sudo loft-ctl start mercurius`.
2. Open `https://mercurius.loft.hsimah.com`. The setup wizard creates the first admin account, then the first space: name it `household`, bound to `mercurius.loft.hsimah.com` at `/`.
3. In the dashboard, create the second account and add it to `household` with `write`. Set each account's full name and email; commits are attributed to them.
4. In Forgejo, create a private, empty repository `hsimah/mercurius`.
5. At `https://mercurius.loft.hsimah.com/.dashboard/household/git` → **Connect repository**: URL `ssh://git@kennl.loft.hsimah.com:2222/hsimah/mercurius.git`, **Deploy key for this space**, generate it, and add the public key under the Forgejo repository → Settings → Deploy keys **with write access**. Then **Check connection** and **Enable sync**.
6. Check `loft-ctl health mercurius`, then confirm a page edit appears as a commit in Forgejo within a minute.

## Backups

Forgejo holds the space's history on the same host, which is not a backup. Off-site backup of `/mammoth/mercurius` is [built but shelved](../operations/backups.md); until it returns, the folder and Forgejo are both lost with space-needle.

## Upgrades

Pin the `-slim` version tag. After an upgrade, reload the browser twice so the service worker picks up the new client.

## Troubleshooting

- **Git sync fails to connect**: the container resolves `kennl.loft.hsimah.com` through Mushr's DNS (`dns:` in Compose). Check the deploy key has write access, and that `ssh` works as littledog's UID: it refuses users without a passwd entry, which the entrypoint creates.
- **Space not found or redirects to the dashboard**: the space is bound to a different hostname than the one in the browser.
- **Logs say `boot mode: single-space`**: a legacy `SB_*` variable is set, or `/mammoth/mercurius` held files before the first boot. Multi-space setup only runs on an empty data folder with no legacy variables.
- **Conflicts**: the space's **Git: Review conflicts**. Edit pages through the wiki, not in Forgejo's web editor.
