# Clog — inventory on Viking

Public service verified by the operator; backup/recovery follow-ups remain. The app now runs on
Nginx + PHP-FPM + SQLite, without WordPress, MySQL or Redis. The URL is
`https://clog.hsimah.com/`; frontend routes start at `/`.

```text
Cloudflare → viking-prod tunnel → mushr:8080 (Caddy) → clog:8080 (Nginx)
                                                          ↓ Unix socket
                                                       clog-php
                                                          ↓
                                                       SQLite
```

[Compose](../../services/clog/docker-compose.yml) runs Nginx on an internal
network shared only with Caddy. FPM and the administrative CLI have network mode
`none`. Neither runtime publishes host ports. Only PHP mounts the database;
Nginx sees static assets and a read-only socket-directory mount. Code is an
immutable, checksum-named release directory. Both runtimes use UID/GID 1003,
read-only roots, dropped capabilities and bounded resources/logs.

The dedicated network uses `172.30.93.0/29`, with Caddy at `172.30.93.2`.
[Nginx](../../services/clog/nginx.conf) trusts client identity only from that
address. Caddy overwrites the application header with Cloudflare's client IP.
Local host probes share Caddy's fallback identity. Check subnet conflicts before
starting; if changing the subnet, update both Compose IPAM and Nginx's trusted IP.

PHP starts with two on-demand workers and a 64 MiB allocation limit. The container
limit is 256 MiB; Nginx has 48 MiB. These are starting settings, not a claim of Pi
capacity. Measure total host memory, latency and concurrent search/write behavior.
SQLite must stay on local storage. Session cleanup uses PHP's probabilistic GC;
sessions expire in the application after eight hours even before files are removed.

## Deploy with one command

From the reviewed checkout on Viking (normally `/srv/the-loft`, or `~/loft`):

```bash
loft-ctl deploy clog
```

The command asks for sudo if needed. It reads the approved version, URL and SHA-256
from [the release pin](../../hosts/viking/clog-release.json). To preview without
host changes, use `loft-ctl deploy clog --plan`. `setup.sh` prepares the host and
leaves Clog installation to this command. It never installs a database as a side
effect of general fleet provisioning.

The deploy command:

1. Checks the Viking role, DMZ attestation, firewall and Docker. It warns when
   Docker cannot enforce memory limits; it does not edit boot settings or reboot.
2. Downloads and verifies the pinned standalone archive, stages it under its
   checksum and prepares private writable directories. An existing release is
   reused only after comparing its contents against the verified archive.
3. Pulls runtime images and validates Compose, PHP extensions, FPM, Nginx and
   Caddy before stopping Clog. Caddy validation uses an isolated container so it
   cannot collide with the running proxy's fixed network address.
4. Applies the proxy/network configuration and checks the existing websites.
   The first managed deployment refreshes Caddy once; later runs force a refresh
   only when the proxy configuration changes. A refresh briefly interrupts its
   sites. It does not recreate the tunnel or Pawst.
5. Stops Clog writes, backs up any existing database using the previous release's
   SQLite backup command, and runs the selected release's explicit installer.
6. Creates the first editor account only if none exists. Username/password prompts
   happen before downtime; passwords are hidden, confirmed and passed through
   stdin. Existing accounts and inventory are preserved.
7. Selects the release in `.env`, recreates Nginx/FPM, waits for readiness and
   checks Clog's health/login endpoints plus both existing websites through Caddy.
8. Records success and prints the public URL, backup path and first-cutover
   Cloudflare settings. DNS and Cloudflare remain operator-managed.

An existing installation from the manual walkthrough is supported: the command
reads its `.env` and database, verifies the existing staged release, takes a
backup and preserves accounts. No reinstall/reset is required. Normal runs use
one deployment lock so concurrent invocations cannot modify the database.

For a pre-downloaded or private release, supply a local archive with
`loft-ctl deploy clog --archive /path/to/clog-standalone.tar.gz`. The manifest's
checksum is still enforced. The default download is the pinned public GitHub
asset. Use `--user NAME` to preselect the first username; it does not change any
existing account.

To update the app, review and change the release pin in Git, pull that reviewed
configuration on Viking and run `loft-ctl deploy clog` again. The command does not
pull Git, choose “latest”, run Composer or build frontend assets. Use this command
for Clog releases instead of generic `loft-ctl update`/`rebuild`.

### Deployment state and failures

State lives under `/var/lib/loft/deploy/`:

- `clog.json`: last successful release, directory, proxy fingerprint, backup and time.
- `clog-pending.json`: interrupted/failed operation phase, previous directory and backup.
- `clog.lock`: serializes deployments.

Download/checksum/image/config failures occur before Clog is stopped. Once writes
are stopped, a failure leaves Clog stopped and retains the pending record. The
script does not automatically run old code against a potentially migrated
schema. Further deployments refuse to proceed until the operator resolves the
record using the recovery procedure below. Existing sites remain separate.

No public exposure or external login is inferred from local health. Complete the
Cloudflare and external acceptance steps below on first installation.

## 3. Cloudflare — do this after the private checks pass

**This is the point to log into Cloudflare and add the public route.** Certificate
coverage can be checked earlier without exposing the app.

In the `hsimah.com` zone, confirm the existing `*.hsimah.com` edge certificate
is active. It covers `clog.hsimah.com`; no advanced certificate add-on is needed.
See [Cloudflare's wildcard coverage](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/).

In Cloudflare One, open **Networks → Connectors → Cloudflare Tunnels →
`viking-prod` → Published application routes** (some dashboards call these public
hostnames). Add:

| Field | Value |
| --- | --- |
| Subdomain | `clog` |
| Domain | `hsimah.com` |
| Path | Leave blank; all app routes |
| Service type | HTTP |
| URL | `mushr:8080` |
| HTTP Host Header | `clog.hsimah.com` |

Caddy forwards that exact hostname to Nginx. Do not use `localhost`: inside the
connector that would refer to the connector container. Preserve both existing
Pawst routes and the final unmatched-host 404; do not add a wildcard or private
network route.

Confirm the dashboard created a **proxied CNAME** for `clog` targeting the
actual `viking-prod` tunnel ID followed by `.cfargotunnel.com`. If an existing DNS
record conflicts, inspect it before replacing it. Tunnel ID in the existing
restore record is `77cdbc17-f2cb-4977-88e1-1fc4337e909c`; verify against the dashboard.
See [Cloudflare tunnel DNS records](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/).

Add a cache rule for this hostname to **bypass cache** initially, and enforce HTTPS
at the edge. Clog supplies private/no-store for dynamic responses. Keep browser
challenges away from GraphQL/AJAX routes. Disable Pseudo IPv4 header overwriting
for this route/zone if enabled so rate limiting receives the actual client IP.
Clog's own login protects inventory; no additional Access identity gate is assumed.

## 4. LAN DNS and external acceptance

`clog.hsimah.com` is outside the LAN's `*.loft.hsimah.com` wildcard, so no
space-needle DNS change is needed. Verify it resolves to public Cloudflare
addresses from the LAN. Test on cellular and LAN:

- HTTPS certificate valid; `/healthz` succeeds and login works.
- Inventory read/write, deep links, assets, session expiry and logout work.
- Anonymous GraphQL POST returns 401; invalid CSRF returns 403.
- `.env`, PHP paths, database paths and unknown hosts are unavailable.
- Dynamic responses bypass edge caching; client addresses in Nginx logs vary
  correctly across external clients. Forged `X-Clog-Client-IP` cannot bypass limits.
- Existing Pawst sites and monitoring remain healthy. Repeat host/container
  isolation probes and measure memory/concurrency on Viking.

After backup restoration is rehearsed, perform a controlled reboot and repeat
health checks. Record the actual deployment date, release checksum, image digests
and external/reboot results in the host runbook. Repository edits alone are not
proof of a running service.

## Backups, updates and recovery

Create a consistent SQLite backup with the app's `VACUUM INTO` command; never
copy only the live main database while WAL writes are active:

```bash
sudo docker compose --env-file services/clog/.env \
  -f services/clog/docker-compose.yml run --rm --no-deps -T \
  clog-cli backup /var/lib/clog/backup-YYYYMMDD-HHMM.sqlite
```

Choose a new filename each time. The host file is beneath `/var/lib/clog/data`.
Transfer it to encrypted off-host storage; it contains password hashes. Record
and retain the matching app archive/checksum and infrastructure configuration.
Set up a daily backup schedule and failure monitoring before storing real data;
backup transport/credentials are not provisioned by this change. Delete local
backup copies only after verifying off-host recovery. Sessions need not be backed up.

For updates, change the reviewed release pin and run `loft-ctl deploy clog`.
Each deployment with existing data creates a local `pre-deploy-*.sqlite` snapshot
after stopping writes. Copy snapshots off-host; scheduled encrypted backups and
retention are still separate operational work.

For database rollback, stop both services, move the current database **and any
`-wal`/`-shm` sidecars** into a recovery directory, restore the matching backup as
`/var/lib/clog/data/clog.sqlite` with owner `1003:1003` and mode `0600`, clear session
files, select the matching release in `.env`, then start and verify. Never replace
a database beneath running workers. An app-only rollback is safe only if its
schema remains compatible. Rehearse restoration in an isolated copy first.

After an interrupted deployment, inspect `clog-pending.json` before retrying.
If its phase is `stopping`, no installer was invoked; resolve the stop/backup
failure and restart the selected old release if appropriate. If it says
`backed-up` or `installing`, retain the recorded backup and follow the matching
release/database restore procedure above, or diagnose and explicitly complete the
selected migration. A pending record with no previous database is a failed fresh
installation; inspect its schema/account state before continuing.

After verifying the recovered release and database, move the pending record into
an incident archive under `/var/lib/loft/deploy/` so a subsequent deployment can
proceed. Do not delete it merely to bypass an unresolved migration. The command
prints its location on failure.

For a failed first cutover, remove only Clog's published route and stop its two
runtime containers; preserve data for diagnosis. Caddy/Pawst need not be rolled
back. See the [Viking restore runbook](../operations/viking-restore.md) for the host
boundary and existing public services; replay this runbook for Clog after that.

## Local validation

On 2026-09-27, the available standalone archive passed the disposable local
Nginx/FPM runtime test: readiness, secure login cookies, CSRF checks, GraphQL,
logout, deep links/assets, denied paths, body limits, forged-header throttling
and SQLite backup. The test uses rootless Podman on the workstation; its tmpfs
uses mode 1777 because Podman's CLI rejects Docker's uid/gid tmpfs options.
Production retains UID/GID-owned mode 1770 tmpfs. CI is configured to validate
that setup with Docker; the initial deployment PR passed both CI jobs. This does not establish ARM performance or live network isolation.

Compose isolation and archive-extraction regressions, existing repository tests,
Caddy/dnsmasq configuration validation and local documentation links also passed.
Rerun against the final selected artifact before promotion:

```bash
python3 tests/clog-runtime.py /path/to/clog-standalone.tar.gz
```

The test creates only temporary local containers/storage and a loopback port.
It does not connect to Viking. CI validates server configurations and repository
regressions; the runtime test needs an app archive and is run separately.

## Operator rollout record

On 2026-09-27 the operator staged standalone release `0.1`, SHA-256
`91ab6b72fb196f0d11a8c9534064100c26db52016254bbb44b87361dd85b280b`,
initialized SQLite and created an editor account. Both images reported arm64.
Caddy and both Clog containers became healthy; existing sites and the private
Clog health endpoint passed. After the hostname correction, the operator verified `clog.hsimah.com` locally
and over cellular, including login and creating, reloading, viewing from another
device and deleting a test location. The Cloudflare route is serving the app.

Docker reported no memory/swap limit support. The active boot command line has
`cgroup_disable=memory` and cgroup v2 exposes no memory controller. The operator
explicitly deferred boot changes/reboot to finish bringing up the app. Compose
memory limits are therefore **not enforced** on Viking; PHP's request allocation
limit and worker count still apply. Enabling the controller, checking actual
cgroup limits, off-host backup/restore and reboot acceptance remain follow-ups.

## Deployment command validation

The deployment state machine is tested with disposable SQLite databases and
mocked host commands: first install, repeat deployment, preserved accounts/data,
backup ordering, checksum/pull/backup/migration/health failures, concurrent runs
and side-effect-free plans. These tests do not operate on Viking. The command
itself has not yet been run on the live host.
