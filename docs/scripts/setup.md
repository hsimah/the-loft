# loft-ctl setup

`loft-ctl setup` ([source](../../control-plane/setup.sh)) provisions a Debian/Ubuntu host from `hosts/$(hostname)/host.conf`. It runs as root, elevating with sudo; it is repeatable but has side effects.

```bash
loft-ctl setup
```

| Input | Effect |
|---|---|
| Hostname | Selects host.conf; unknown hosts fail |
| Storage fields | Adds fstab entry and mounts; never formats or rewrites an existing entry |
| Users | Creates `pack-member`/`littledog` as 1003 if absent; adds groups. Removes littledog from `sudo` everywhere and, on `PRODUCTION_ROLE=true`, from Docker |
| SSH fields | Restricts SSH to adminhabl; optionally disables passwords |
| `CONFIG_DIRS` / `MEDIA_DIRS` | Creates dirs; resets top-level owner to littledog:pack-member, mode 755/775 |
| `SERVICES` + `.env` | Validates and starts each service with host overrides; skips a service whose Compose config fails. A missing `.env` fails only where Compose reads it (`env_file`) or requires a variable (`${VAR?}`); otherwise the service starts with empty values |
| Service hook (`services/<name>/setup.sh`) | Sourced after deploy; no service has one at present |
| `hosts/<host>/bootstrap` | Host provisioning (Surface kiosks: i3, dashboard, power daemon, hardware fixes; Fjord: Bluetooth audio; space-needle and helarctos: egress firewalls) |
| Wi-Fi fields | Installs the watchdog script, defaults file and cron |
| `BACKUP_*` | With `BACKUP_ENABLED=true`: installs restic and rclone, `loft-backup`, and the nightly and weekly systemd timers ([backups](../operations/backups.md)) |

It also installs base packages, Docker (if missing), Git hooks, the `loft-proxy` network, Fastfetch with [laiko.txt](../../laiko.txt), and copies [daemon.json](../../daemon.json) — **which restarts Docker if it changed**. It overwrites adminhabl's `.bashrc`, `.inputrc` and `.tmux.conf` with includes of the repo's dotfiles, and rewrites SSH/sudoers config.

It does not stop services removed from the manifest; stop them first. Rerun after changing directories, groups, cron, bootstrap/watchdog scripts, dotfiles or daemon settings — `loft-ctl update` does not refresh files copied into `/usr/local/bin`.

Kiosk wallpaper: supply `/home/rodnik/Pictures/wallpaper.webp` by hand; `Mod+Shift+r` reloads i3.

## Fresh host

1. Install a minimal OS with user `adminhabl` and key SSH. Pis: Raspberry Pi OS Lite 64-bit. Surfaces: see [Calavera reimage](../hosts/calavera.md#reimage).
2. Add adminhabl's key to `hsimah/the-loft` on [kennl](../services/kennl.md), add a `~/.ssh/config` block for `kennl.loft.hsimah.com` (`Port 2222`, `User git`, `IdentityFile`, `IdentitiesOnly yes`; without it ssh offers no key), then clone:

   ```bash
   sudo install -d -o adminhabl -g adminhabl /srv/the-loft
   git clone ssh://git@kennl.loft.hsimah.com:2222/hsimah/the-loft.git /srv/the-loft
   ```

   Viking cannot reach kennl; it clones the GitHub mirror `git@github.com:hsimah/the-loft.git` instead.

3. Create each service's `.env` from its example (Houstn `COMPOSE_PROFILES=metrics`, [Snoot](../services/snoot.md) with a new Beszel system).
4. Run `/srv/the-loft/loft-ctl setup` (the alias arrives with the dotfiles setup installs). Keep the first SSH session open while testing a new key login and `sudo`.
5. Check `sudo sshd -T | grep -E 'allowusers|passwordauthentication'`, `id littledog`, mounts, cron and `loft-ctl health`.

Viking additionally needs `/etc/loft/dmz-ready` and follows [Viking restore](../operations/viking-restore.md); setup alone does not install its firewall, Tailscale, secrets or site content.

If Docker fails to restart: `sudo journalctl -u docker --since '5 min ago'` and the installed `/etc/docker/daemon.json`.
