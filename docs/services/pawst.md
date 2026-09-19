# Pawst — static sites

[Compose](../../services/pawst/docker-compose.yml) runs one nginx container on space-needle's `loft-proxy` network. [nginx.conf](../../services/pawst/nginx.conf) selects a document root by hostname; Caddy supplies ingress. There are no host-published nginx ports and no service `.env`.

| Site | Host document root | Release source/status |
|---|---|---|
| `hbla.ke` | `/opt/pawst/hblake-html` | `hsimah-services/hblake` |
| `hsimah.com` | `/opt/pawst/hsimah-html` | `hsimah-services/hsimah` |

Public tunnel hostnames are a manual Cloudflare setting; Caddy routes alone do not prove external deployment. An empty document root is not a successful site deployment; with the SPA fallback, a missing index may also produce an error rather than the expected 404.

## Deployment

[DEPLOY_TARGETS](../../hosts/space-needle/host.conf) drives hourly cron; the [release puller](../scripts/deploy-pull.md) downloads `.tar.gz` assets and syncs the bind-mounted directories in place. nginx reads them without a reload. Site directories are mounted read-only into nginx; the container itself is not configured with a read-only root filesystem.

```bash
sudo /srv/the-loft/control-plane/deploy-pull.sh \
  pawst-hblake hsimah-services/hblake /opt/pawst/hblake-html
loft-ctl health pawst
```

For a new site: publish its release artifact, add the host config directory/deploy target, nginx mount/server block and Caddy route, then provision/recreate the affected services. Reload Caddy with `sudo docker exec mushr caddy reload --config /etc/caddy/Caddyfile` for route-only changes. There is no `loft-ctl reload`.

For external access, configure the tunnel hostname pointing to HTTPS `mushr:443` with the matching origin server name, then test from outside the LAN. Verify each hostname's configuration rather than assuming every route is public.

## Troubleshooting

- **Old content:** inspect `/var/log/loft/deploy.log`, the target's version marker and the latest release asset. Same-tag replacement does not trigger a redeploy. `/assets/` is cached immutably, so builds should use content-hashed names.
- **Wrong site/missing route:** inspect Host-based routing at both Caddy and nginx. `hblake.space-needle` is covered by DNS and nginx but has no matching Caddy route; use `pawst.space-needle` or add that route deliberately.
- **Missing index:** inspect the correct host document root. Both blocks use SPA fallback; that does not create an index for an undeployed site.
- **Only external access fails:** check [Mushr's](mushr.md) tunnel logs and Cloudflare hostname configuration. LAN DNS bypasses the tunnel, so testing hbla.ke from home is not an external-access test.
