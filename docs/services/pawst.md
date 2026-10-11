# Pawst — static sites

Production on Viking via its [override](../../hosts/viking/overrides/pawst/docker-compose.override.yml): non-root nginx, read-only root and content, internal network, no host ports. Fjord's [override](../../hosts/fjord/overrides/pawst/docker-compose.override.yml) runs dev/test.

| Site | Content | Source |
|---|---|---|
| `hsimah.com` | Blog, `/opt/pawst/prod/hsimah` | `hsimah-services/hsimah` releases, state name `pawst-hsimah` |
| `hbla.ke` | Holding page, [`services/pawst/holding`](../../services/pawst/holding/) | This repo; `/posts/*` 302s to hsimah.com |

The consulting site (`hsimah-services/hblake`) replaces the hbla.ke holding page when it deploys; see [open work](../../plans/maintenance.md).

## Deploy and roll back

No cron and no pin in Git. On Viking:

```bash
loft-ctl deploy pawst hsimah          # latest GitHub release
loft-ctl deploy pawst hsimah "$TAG"   # a specific release, e.g. rollback
```

[pawst-deploy.sh](../../control-plane/pawst-deploy.sh) resolves the tag, takes the checksum from GitHub's asset `digest`, runs the [release puller](../scripts/deploy-pull.md) and checks the site locally. The deployed tag is in `/var/lib/loft/deploy/pawst-hsimah.version`. Sync is in place, not atomic. The holding page changes with `loft-ctl update pawst`.

[Restore](../operations/viking-restore.md) fetches the blog's GitHub **latest** release. After rolling back, unmark or delete the bad release on GitHub so a restore does not bring it back.

## Ingress

Tunnel `viking-prod` has exactly the two hostname routes to `http://mushr:8080`, then a catch-all 404. Each apex is a proxied CNAME to the tunnel. LAN DNS resolves both via public upstreams.

## Troubleshooting

- **Old content**: `/var/lib/loft/deploy/pawst-hsimah.version`/`.sha256`; see [release puller](../scripts/deploy-pull.md).
- **Missing index**: health requires the blog deployed and the holding page mounted.
- **Local curl hangs**: the host firewall's TCP 8080 → `br-*` exception for docker-proxy.
- **External failure**: `mushr-tunnel` logs, token, allowed 7844 egress, Cloudflare route/DNS.
