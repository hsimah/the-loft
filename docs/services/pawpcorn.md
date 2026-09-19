# Pawpcorn — Plex

[Compose](../../services/pawpcorn/docker-compose.yml) runs Plex on space-needle with host networking, port 32400, `/dev/dri` passthrough and library mounts from `/mammoth`. Caddy provides `https://pawpcorn.loft.hsimah.com`; direct LAN access is `http://192.168.86.28:32400/web`.

## Configuration and data

Copy [.env.example](../../services/pawpcorn/.env.example). `PUID`/`PGID` map to `PLEX_UID`/`PLEX_GID`; the current example uses 1004/1003. Fresh setup creates littledog as 1003, but preserves existing IDs. Check `id littledog` and actual Plex data ownership before choosing values; do not change an existing installation's ownership from the example alone.

- `/opt/pawpcorn/config`: library DB, metadata, watch state and server configuration.
- `/mammoth/pawpcorn/transcode`: temporary transcoding workspace.
- `/mammoth/library/*`: movies, TV, music, videos and stand-up, mounted under `/data`.

First claim uses `PLEX_CLAIM` from [Plex](https://plex.tv/claim). Obtain it immediately before first startup. For claim failure, inspect logs and the account association; do not delete Preferences.xml as a routine fix.

## Upgrades and verification

```bash
loft-ctl rebuild pawpcorn
loft-ctl health pawpcorn
sudo docker logs pawpcorn --tail 100
sudo docker exec pawpcorn ls -ln /dev/dri
```

Rebuild pulls the configured pin, not a newer release automatically. Before changing it, take a stopped-service backup as described in [upgrades](../operations/upgrades.md). Verify libraries, direct play and a hardware transcode after starting; database migration may take longer than the health-check window.

Hardware transcoding requires Plex Pass, the device nodes and effective access by the Plex process. Host littledog membership in render/video alone does not prove the in-container groups are correct. Inspect both process identity and device permissions before modifying either.

For missing files, inspect mount contents and library paths/types. Imports come from [Stellarr](stellarr.md); the current separate import mounts do not guarantee hardlinks. Stop Plex before removing confirmed stale transcode scratch files. Preserve the config tree.

Plex's Remote Access/Relay configuration lives outside these manifests. Verify its current state before claiming it is LAN-only or adding any router forwarding.
