# Clog — inventory on Viking

`https://clog.hsimah.com/`: Nginx + PHP-FPM + SQLite, deployed on Viking from the [release pin](../../hosts/viking/clog-release.json).

```text
Cloudflare → viking-prod tunnel → mushr:8080 (Caddy) → clog:8080 (Nginx) → clog-php (Unix socket) → SQLite
```

- [Compose](../../services/clog/docker-compose.yml): Nginx is on an internal network shared only with Caddy (`172.30.93.0/29`, Caddy at `.2`). FPM and the CLI have `network_mode: none`. Only PHP mounts the database. Code is an immutable checksum-named release directory. UID/GID 1003, read-only roots, dropped capabilities.
- [Nginx](../../services/clog/nginx.conf) trusts the client-IP header only from `172.30.93.2`; Caddy overwrites it with Cloudflare's client IP. If you change the subnet, change both Compose IPAM and Nginx.
- PHP: two on-demand workers, 64 MiB per request; container limits 256 MiB (PHP) / 48 MiB (Nginx), **not enforced** on Viking (see [host page](../hosts/viking.md#constraints)).
- Sessions expire after eight hours. SQLite must stay on local disk.

## Deploy and update

```bash
loft-ctl deploy clog --plan   # preview, no changes
loft-ctl deploy clog
```

To update, change the pin in Git, pull on Viking, rerun. Do not use `loft-ctl update`/`rebuild` for Clog. `--archive PATH` uses a local archive (checksum still enforced); `--user NAME` preselects the first username.

Deploys never grant administration (user management, from 1.0). Grant an existing account once:

```bash
sudo docker compose --env-file services/clog/.env \
  -f services/clog/docker-compose.yml run --rm --no-deps -T \
  clog-cli user:admin NAME
```

The command checks the role/firewall/Docker, downloads and verifies the archive, validates images and config **before** stopping Clog, refreshes Caddy only when its config changed, stops writes, backs up the DB (`pre-deploy-*.sqlite`), runs the release installer, creates the first account only if none exists, recreates Nginx/FPM and checks Clog plus both Pawst sites. It never pulls Git or touches Cloudflare.

State in `/var/lib/loft/deploy/`: `clog.json` (last success), `clog-pending.json` (interrupted run), `clog.lock`.

A failure after writes stop leaves Clog stopped and the pending record in place; further deploys refuse until it is resolved:

- Phase `stopping`: no installer ran. Fix the cause and restart the old release.
- Phase `backed-up`/`installing`: keep the recorded backup; restore it (below) or finish the migration deliberately.
- No previous database: a failed fresh install; inspect schema/accounts.

Then move the pending record into an archive directory under `/var/lib/loft/deploy/` — never delete it just to unblock a deploy.

## Public route

`viking-prod` → Published application routes: `clog.hsimah.com`, HTTP, URL `mushr:8080`, HTTP Host Header `clog.hsimah.com` (not `localhost`, which would be the connector itself). It needs a proxied CNAME to the tunnel, a cache-bypass rule, edge HTTPS, and Pseudo IPv4 disabled so rate limits see real IPs. `*.hsimah.com` universal SSL covers it; no LAN DNS change is needed.

## Backups and recovery

Use the app's `VACUUM INTO` backup; never copy the live file while WAL is active:

```bash
sudo docker compose --env-file services/clog/.env \
  -f services/clog/docker-compose.yml run --rm --no-deps -T \
  clog-cli backup /var/lib/clog/backup-YYYYMMDD-HHMM.sqlite
```

The file lands under `/var/lib/clog/data`. It contains password hashes: move it off-host encrypted. No scheduled backup exists yet.

Rollback: stop both containers, move `clog.sqlite` **and** its `-wal`/`-shm` files aside, restore the backup as `/var/lib/clog/data/clog.sqlite` (1003:1003, 0600), clear sessions, select the matching release in `.env`, start and verify. App-only rollback is safe only if the schema is unchanged.

## Testing

`python3 tests/clog-runtime.py /path/to/clog-standalone.tar.gz` runs a disposable local Nginx/FPM stack (rootless Podman is fine) covering login, CSRF, GraphQL, denied paths, throttling and backup. Run it against a new archive before changing the pin.
