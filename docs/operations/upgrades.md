# Upgrades, backups and rollback

Image references live in Compose, not duplicated version tables. Upgrade one service group at a time, with Music Assistant and Plex verified independently. Use the current manifest, not historical migration plans.

## Before an upgrade

1. Record the running image ID/version and active profiles on the target host. Confirm disk space and the application's supported upgrade/rollback path.
2. Stop only the group whose persistent data needs a consistent backup. Back up its configuration/databases and required secrets, using a unique destination outside those data directories. Do not stop the entire Docker daemon for a single-service backup.
3. Verify the backup can be read and record its matching image version. For large databases use the application's supported backup mechanism; a tar of a live database is not necessarily consistent.
4. Pull the intended new images before taking production down. If the new manifest is not on the host yet, pull the explicit new reference; pulling an old checkout's Compose file warms the old version. Build local images before replacing their running containers.

Example cold backup for Music Assistant (on space-needle, using a unique filename):

```bash
sudo mkdir -p /mammoth/backups
loft-ctl stop howlr
sudo tar -czf /mammoth/backups/howlr-$(date +%Y%m%dT%H%M%S).tar.gz -C /opt howlr
# Verify the newly created archive before starting the upgrade.
loft-ctl start howlr
```

If the backup fails, keep the original data intact and resolve that failure before proceeding. Local backups on `/mammoth` do not protect against loss of the whole host/disk.

## Deploy and verify

Commit the intended pin/config change, then `loft-ctl update <service>`. If the checkout was already updated, use `loft-ctl update --no-pull <service>`. Rebuild alone does not run health checks. After readiness checks, inspect logs and test the actual application.

| Service | State to preserve / acceptance check |
|---|---|
| Howlr | `/opt/howlr`; providers, Upstairs/Downstairs/All playback, Calavera kiosk login and screen wake; recheck stream IDs after player/group changes |
| Pawpcorn | `/opt/pawpcorn/config`; database plus server settings/metadata; libraries, direct play and hardware transcode |
| Pupyrus | `/opt/pupyrus/html` and `/opt/pupyrus/db`; WordPress login, page reads and writes, plugin/cache behavior |
| Stellarr | Per-product `/opt` dirs; client connections, imports and actual VPN egress |
| Houstn | Beszel/Kuma data; upgrade hub before agents; verify fresh remote metrics and widgets |
| Sputnik | WebUI/n8n state plus encryption key; model availability and a successful briefing execution |
| Mushr | Caddy named volumes and environment; DNS, TLS, upstream routes and tunnel from an external network |

## Rollback limits and pin exceptions

Reverting a manifest changes software/configuration, not migrated data. Restore the backup matching the old version if required, with the service stopped. Preserve the failed state separately for diagnosis rather than deleting it before a verified restore. Old images may have been pruned; record/preserve the image reference and availability in advance.

- Snapclient and NordVPN use digest-qualified `latest` references because their tag history did not provide a suitable version pin. The VPN's older `v3.12.3` tag failed authentication in the recorded July incident.
- Lidarr's selected nightly DB was ahead of the stable line. A switch to stable is a data-migration project, not a tag cleanup.
- Kuma 1.x, MariaDB 12.2 and Redis 7 are deliberately held; assess their state migrations separately.
- Caddy's local build uses an unversioned Cloudflare module source. Preserve the prior built image for rollback; the tag alone is not fully reproducible.
- Jackett has application auto-update enabled. Verify the effective version before claiming the Compose tag fully determines its runtime.

Open replacement/reproducibility work is in [maintenance](../../plans/maintenance.md).
