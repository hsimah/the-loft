# Clog — inventory on Viking

Prepared configuration; **not yet deployed or published**. The app now runs on
Nginx + PHP-FPM + SQLite, without WordPress, MySQL or Redis. The URL is
`https://clog.loft.hsimah.com/`; frontend routes start at `/`.

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

## 1. Prepare the host and release

Run the commands on **Viking** from the reviewed checkout at `/srv/the-loft`.
Keep the existing tunnel running for Pawst. Do not run a whole-fleet rebuild.
The existing DMZ attestation and firewall must already be in place.

```bash
cd /srv/the-loft
sudo test -f /etc/loft/dmz-ready
sudo systemctl is-active loft-firewall.service
uname -m
free -m
df -h / /var/lib
sudo docker network ls
sudo docker network inspect $(sudo docker network ls -q) --format '{{.Name}} {{json .IPAM.Config}}'
```

Select the final **standalone** archive `clog-standalone.tar.gz` produced and
verified by the app release workflow. Obtain its independently recorded SHA-256
from that release/build record. Transfer it to Viking or download it there using
the existing GitHub credentials. Do not use the old WordPress ZIP or install
Composer/Node on Viking. The local development archive used for infrastructure
verification is not automatically selected for production.

```bash
# Replace this value with the approved release's actual SHA-256.
CLOG_SHA256=REPLACE_WITH_APPROVED_SHA256
sudo python3 services/clog/stage-release.py /tmp/clog-standalone.tar.gz "$CLOG_SHA256"
sudo install -d -o 1003 -g 1003 -m 0700 \
  /var/lib/clog/data /var/lib/clog/data/sessions /var/lib/clog/runtime
printf 'CLOG_RELEASE_DIR=/opt/clog/releases/%s\n' "$CLOG_SHA256" > services/clog/.env
chmod 600 services/clog/.env
```

The staging tool verifies the checksum, rejects links/path traversal, checks
required release files and refuses to overwrite an existing release. It does not
switch the running app. Preserve `.env`, the checksum, release archive and the
infrastructure commit in the deployment record.

Define this helper in your current Bash session; all following `clog_compose`
commands use it:

```bash
clog_compose() {
  sudo docker compose --env-file /srv/the-loft/services/clog/.env \
    -f /srv/the-loft/services/clog/docker-compose.yml "$@"
}
clog_compose config --quiet
clog_compose --profile tools pull
clog_compose run --rm --no-deps --entrypoint php clog-cli -r \
  'foreach (["pdo_sqlite", "mbstring", "Zend OPcache"] as $e) { if (!extension_loaded($e)) { fwrite(STDERR, "$e missing\n"); exit(1); } }'
clog_compose run --rm --no-deps --entrypoint php-fpm clog-cli \
  --test --fpm-config /usr/local/etc/clog-fpm.conf
clog_compose run --rm --no-deps clog-cli install
```

Confirm the pulled images are arm64 using `sudo docker image inspect` and record
their RepoDigests. Runtime image pins follow the fleet's version-tag convention;
the app is separately pinned by archive checksum. Check memory headroom before
starting additional services.

Create your editor account with a password of 12–72 bytes. Passwords go through
stdin, never command arguments or a committed file. `reader` grants read-only
inventory access. There is no registration or email reset flow; keep credentials
in your password manager. The current CLI creates accounts but does not reset or
disable existing ones; add that recovery capability in the app before relying on
it for unattended operation.

```bash
sudo -v
read -rsp 'Clog password: ' CLOG_NEW_PASSWORD
printf '\n'
printf '%s' "$CLOG_NEW_PASSWORD" | clog_compose run --rm --no-deps -T clog-cli user:add admin editor
unset CLOG_NEW_PASSWORD
```

## 2. Attach Nginx and verify the private origin

Caddy owns the new internal network. Its network membership changes, so a Caddy
reload alone is insufficient. Validate its configuration, then recreate only
`mushr`; expect a short interruption to the existing sites. This leaves the
running tunnel and Pawst containers intact.

```bash
sudo docker compose -f services/mushr/docker-compose.yml \
  -f hosts/viking/overrides/mushr/docker-compose.override.yml \
  run --rm --no-deps mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker compose -f services/mushr/docker-compose.yml \
  -f hosts/viking/overrides/mushr/docker-compose.override.yml \
  up -d --no-deps --wait mushr
clog_compose run --rm --no-deps --entrypoint nginx clog -t
clog_compose up -d --wait
curl --noproxy '*' --fail-with-body -H 'Host: clog.loft.hsimah.com' http://127.0.0.1:8080/healthz
curl --noproxy '*' --fail -o /dev/null -H 'Host: clog.loft.hsimah.com' http://127.0.0.1:8080/auth/login
curl --noproxy '*' --fail -o /dev/null -H 'Host: hsimah.com' http://127.0.0.1:8080/
curl --noproxy '*' --fail -o /dev/null -H 'Host: hbla.ke' http://127.0.0.1:8080/
curl --noproxy '*' -o /dev/null -w '%{http_code}\n' -H 'Host: unknown.invalid' http://127.0.0.1:8080/
loft-ctl health clog
sudo docker stats --no-stream clog clog-php mushr pawst
```

Require `{"ok":true}`, a login HTTP 200, both existing sites healthy and unknown
host HTTP 404. Browser sessions require public HTTPS; local HTTP probes do not
prove browser login. Nginx readiness exercises FPM and the SQLite schema. Neither
readiness nor ordinary app startup applies migrations.

## 3. Cloudflare — do this after the private checks pass

**This is the point to log into Cloudflare and add the public route.** Certificate
coverage can be checked earlier without exposing the app.

In the `hsimah.com` zone, first confirm an active edge certificate covers
`clog.loft.hsimah.com` (or `*.loft.hsimah.com`). Standard Universal SSL on a full
`hsimah.com` zone only covers the apex and one subdomain level. This hostname
needs deeper coverage, such as an advanced certificate/Total TLS, unless the
zone already has suitable coverage. Origin certificates do not solve browser-to-
Cloudflare coverage. See [Cloudflare's certificate limitations](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/).

In Cloudflare One, open **Networks → Connectors → Cloudflare Tunnels →
`viking-prod` → Published application routes** (some dashboards call these public
hostnames). Add:

| Field | Value |
| --- | --- |
| Subdomain | `clog.loft` |
| Domain | `hsimah.com` |
| Path | Leave blank; all app routes |
| Service type | HTTP |
| URL | `mushr:8080` |
| HTTP Host Header | `clog.loft.hsimah.com` |

Caddy forwards that exact hostname to Nginx. Do not use `localhost`: inside the
connector that would refer to the connector container. Preserve both existing
Pawst routes and the final unmatched-host 404; do not add a wildcard or private
network route.

Confirm the dashboard created a **proxied CNAME** for `clog.loft` targeting the
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

The space-needle DNS wildcard currently resolves `*.loft.hsimah.com` locally.
The new exact-domain forwarding exception in
[dnsmasq.conf](../../services/mushr/dnsmasq.conf) sends Clog queries to public DNS.
After Cloudflare DNS is ready, update the reviewed checkout on **space-needle**:

```bash
cd /srv/the-loft
sudo docker exec mushr-dns dnsmasq --test
sudo docker compose -f services/mushr/docker-compose.yml restart mushr-dns
```

Restart is needed to reread the config; flush client DNS caches as needed. Verify
`clog.loft.hsimah.com` returns public Cloudflare addresses from LAN DNS, while other
loft names still resolve locally. Test on cellular and LAN:

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
clog_compose run --rm --no-deps clog-cli backup /var/lib/clog/backup-YYYYMMDD-HHMM.sqlite
```

Choose a new filename each time. The host file is beneath `/var/lib/clog/data`.
Transfer it to encrypted off-host storage; it contains password hashes. Record
and retain the matching app archive/checksum and infrastructure configuration.
Set up a daily backup schedule and failure monitoring before storing real data;
backup transport/credentials are not provisioned by this change. Delete local
backup copies only after verifying off-host recovery. Sessions need not be backed up.

For updates: stage a new archive into a new directory, stop Nginx and FPM to pause
writes, create the backup using the old release, change `.env`, run the new
release's explicit `install`, then recreate both services and run smoke tests.
Do not modify the release directory in place: this would violate asset/code and
OPcache consistency. Keep the prior release and backup.

For database rollback, stop both services, move the current database **and any
`-wal`/`-shm` sidecars** into a recovery directory, restore the matching backup as
`/var/lib/clog/data/clog.sqlite` with owner `1003:1003` and mode `0600`, clear session
files, select the matching release in `.env`, then start and verify. Never replace
a database beneath running workers. An app-only rollback is safe only if its
schema remains compatible. Rehearse restoration in an isolated copy first.

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
that setup with Docker; the new CI job has not yet run. This does not establish ARM performance or live network isolation.

Compose isolation and archive-extraction regressions, existing repository tests,
Caddy/dnsmasq configuration validation and local documentation links also passed.
Rerun against the final selected artifact before promotion:

```bash
python3 tests/clog-runtime.py /path/to/clog-standalone.tar.gz
```

The test creates only temporary local containers/storage and a loopback port.
It does not connect to Viking. CI validates server configurations and repository
regressions; the runtime test needs an app archive and is run separately.
