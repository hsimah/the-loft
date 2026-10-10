# Pawst — static sites

Production on Viking via its [override](../../hosts/viking/overrides/pawst/docker-compose.override.yml): non-root nginx, read-only root and content, internal network, no host ports. Fjord's [override](../../hosts/fjord/overrides/pawst/docker-compose.override.yml) runs dev/test.

| Site | Document root | Release repo | State name |
|---|---|---|---|
| `hbla.ke` | `/opt/pawst/prod/hblake` | `hsimah-services/hblake` | `pawst-hblake` |
| `hsimah.com` | `/opt/pawst/prod/hsimah` | `hsimah-services/hsimah` | `pawst-hsimah` |

## Deploy and roll back

No cron and no pin in Git. On Viking:

```bash
loft-ctl deploy pawst hblake          # latest GitHub release
loft-ctl deploy pawst hblake "$TAG"   # a specific release, e.g. rollback
```

[pawst-deploy.sh](../../control-plane/pawst-deploy.sh) resolves the tag, takes the checksum from GitHub's asset `digest`, runs the [release puller](../scripts/deploy-pull.md) and checks the site locally. The deployed tag is in `/var/lib/loft/deploy/pawst-<site>.version`. Sync is in place, not atomic.

[Restore](../operations/viking-restore.md) fetches each site's GitHub **latest** release. After rolling back, unmark or delete the bad release on GitHub so a restore does not bring it back.

## Ingress

Tunnel `viking-prod` has exactly the two hostname routes to `http://mushr:8080`, then a catch-all 404. Each apex is a proxied CNAME to the tunnel. LAN DNS resolves both via public upstreams.

## Troubleshooting

- **Old content**: `/var/lib/loft/deploy/pawst-<site>.version`/`.sha256`; see [release puller](../scripts/deploy-pull.md).
- **Missing index**: health requires both sites deployed.
- **Local curl hangs**: the host firewall's TCP 8080 → `br-*` exception for docker-proxy.
- **External failure**: `mushr-tunnel` logs, token, allowed 7844 egress, Cloudflare route/DNS.
