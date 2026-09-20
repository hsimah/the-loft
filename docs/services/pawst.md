# Pawst — static sites

Production runs on Viking using its [host override](../../hosts/viking/overrides/pawst/docker-compose.override.yml):
non-root nginx, read-only root/content, explicit tmpfs, no added capabilities,
resource limits and an internal application network. Caddy supplies ingress;
nginx publishes no host ports. Both public sites moved on 2026-09-20.

| Site | Production document root | GitHub release repository |
|---|---|---|
| `hbla.ke` | `/opt/pawst/prod/hblake` | `hsimah-services/hblake` |
| `hsimah.com` | `/opt/pawst/prod/hsimah` | `hsimah-services/hsimah` |

Fjord's [override](../../hosts/fjord/overrides/pawst/docker-compose.override.yml)
provides independent dev/test instances; those environments are not public and
have not yet been verified live. See the [platform runbook](../operations/application-platform.md)
for adding applications, promotion and replacement hardware.

## Deployment and rollback

Use approved GitHub release tags and SHA-256 checksums. There is no hourly
latest-release polling on Viking. For example, after setting approved values:

```bash
sudo /srv/the-loft/control-plane/deploy-pull.sh \
  pawst-hblake hsimah-services/hblake /opt/pawst/prod/hblake \
  '' "$HBLAKE_TAG" "$HBLAKE_SHA256"
loft-ctl health pawst
curl --fail-with-body -H 'Host: hbla.ke' http://127.0.0.1:8080/index.html
```

For hsimah.com, use state name `pawst-hsimah`, repository
`hsimah-services/hsimah`, and target `/opt/pawst/prod/hsimah`. nginx reads updated
files without reload. The puller verifies the archive and syncs in place to
preserve bind mounts; this is not an atomic whole-site swap. Roll back with the
previous approved tag/checksum. Retain artifact bytes and test off-host restore.

The [cutover record](../operations/viking-hardening.md#pawst-cutover-record)
contains the first deployed tags/checksums, tests and legacy-host recovery
steps. Space-needle's container is stopped, restart disabled, and cron paused;
its old content is retained. Its manifest, Caddy and tunnel routes no longer
serve Pawst. The shared base Compose/nginx files remain as override inputs and
legacy recovery references, not an active space-needle deployment.

## Public ingress

The separate `viking-prod` tunnel has exactly two hostname routes to
`http://mushr:8080`, followed by a catch-all 404. Cloudflare terminates public
TLS. Caddy routes alone do not publish a site; explicit tunnel routes and
proxied DNS are also required. There is no inbound router port forwarding.

LAN DNS now resolves the public sites through its existing public upstreams,
while `*.loft.hsimah.com` remains local to space-needle. Test from a cellular
connection as well as the LAN. Keep tokens outside Git; see the deployment
record for the token file and permissions.

## Troubleshooting

- **Old content:** check `/var/lib/loft/deploy/pawst-<site>.version` and `.sha256`,
  the deployed directory and the selected archive. State may skip an already
  recorded version; see the runbook before retrying a partial deployment.
- **Wrong site:** check the Host header at Caddy and nginx. Unknown Caddy hosts
  return 404. The old `pawst.space-needle`/`hsimah.space-needle` routes are retired.
- **Missing index:** inspect the production document root. SPA fallback does
  not create an index for an undeployed site; health checks require both indexes.
- **Local curl times out:** check the host-output Docker bridge TCP 8080
  exception needed by docker-proxy; it is distinct from container forwarding.
- **External failure:** inspect `mushr-tunnel` logs, token permissions, allowed
  outbound tunnel destinations, and Cloudflare hostname/DNS configuration.
