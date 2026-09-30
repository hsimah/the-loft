# Pawst — static sites

Production on Viking via its [override](../../hosts/viking/overrides/pawst/docker-compose.override.yml): non-root nginx, read-only root and content, internal network, no host ports. Fjord's [override](../../hosts/fjord/overrides/pawst/docker-compose.override.yml) runs dev/test.

| Site | Document root | Release repo | State name |
|---|---|---|---|
| `hbla.ke` | `/opt/pawst/prod/hblake` | `hsimah-services/hblake` | `pawst-hblake` |
| `hsimah.com` | `/opt/pawst/prod/hsimah` | `hsimah-services/hsimah` | `pawst-hsimah` |

## Deploy and roll back

No cron on Viking; deploy an explicit tag and SHA-256:

```bash
sudo /srv/the-loft/control-plane/deploy-pull.sh \
  pawst-hblake hsimah-services/hblake /opt/pawst/prod/hblake '' "$TAG" "$SHA256"
loft-ctl health pawst
curl --fail-with-body -H 'Host: hbla.ke' http://127.0.0.1:8080/index.html
```

Roll back by running the same command with the previous tag/checksum. Update [releases.json](../../hosts/viking/releases.json) with every production release so [restore](../operations/viking-restore.md) uses it. Sync is in place, not atomic.

## Ingress

Tunnel `viking-prod` has exactly the two hostname routes to `http://mushr:8080`, then a catch-all 404. Each apex is a proxied CNAME to the tunnel. LAN DNS resolves both via public upstreams.

## Troubleshooting

- **Old content**: `/var/lib/loft/deploy/pawst-<site>.version`/`.sha256`; see [release puller](../scripts/deploy-pull.md).
- **Missing index**: health requires both sites deployed.
- **Local curl hangs**: the host firewall's TCP 8080 → `br-*` exception for docker-proxy.
- **External failure**: `mushr-tunnel` logs, token, allowed 7844 egress, Cloudflare route/DNS.
