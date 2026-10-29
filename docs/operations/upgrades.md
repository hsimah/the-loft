# Upgrades, backups and rollback

Upgrade one service group at a time. Pins live in Compose.

## Before

1. Find candidates with [image-updates.sh](../scripts/image-updates.md). Record the running image and active profiles. Check disk space and the app's supported upgrade path.
2. Stop only the group being backed up, copy its state to a unique path outside the data dir, and check the archive reads. Use the app's own dump for large databases.
3. Pull (or build) the new image **before** taking the service down.

```bash
sudo mkdir -p /mammoth/backups
loft-ctl stop howlr
sudo tar -czf /mammoth/backups/howlr-$(date +%Y%m%dT%H%M%S).tar.gz -C /opt howlr
loft-ctl start howlr
```

Backups on `/mammoth` do not survive loss of space-needle, and no off-site backup is running ([backups](backups.md), shelved).

## Deploy and verify

Commit the pin, then `loft-ctl update <service>` (or `--no-pull` if already checked out). Then test the app itself:

| Service | State / acceptance |
|---|---|
| Howlr | `/opt/howlr`; providers, Upstairs/Downstairs/All playback, kiosk login, screen wake |
| Pawpcorn | `/opt/pawpcorn/config`; libraries, direct play, hardware transcode |
| Stellarr | `/opt/<product>`; client connections, imports, VPN egress |
| Houstn | Beszel/Kuma data; upgrade hub before agents |
| Sputnik | WebUI/n8n state + `N8N_ENCRYPTION_KEY`; a chat reply from llama-swap |
| Mushr | Caddy volumes + `.env`; DNS, TLS, routes, tunnel from outside |
| Hubbl | `pg_dumpall` first ([Hubbl](../services/hubbl.md#upgrades)); library browses, a phone upload lands |
| Kennl | `forgejo dump` first; a clone over SSH, a runner job |
| Mercurius | `document_exporter` and `pg_dump` first ([Mercurius](../services/mercurius.md#upgrades)); a document opens with its text, the wiki loads |

## Rollback and pin exceptions

Reverting a pin does not revert migrated data; restore the matching backup with the service stopped. Old images may have been pruned.

- **Snapclient, NordVPN**: digest-pinned `latest`. Never use the VPN's `v3.12.3` tag; it fails authentication.
- **Lidarr**: nightly, because its DB schema is ahead of stable. Moving to stable is a migration, not a tag change.
- **Uptime Kuma 1.x**: deliberately held.
- **Caddy**: local build with an unpinned Cloudflare module; keep the previous image for rollback.
- **Jackett**: `AUTO_UPDATE=true`, so the tag is not the whole version.
