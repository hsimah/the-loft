# Stellarr — media acquisition and audiobooks

[Compose](../../services/stellarr/docker-compose.yml) runs Radarr, Sonarr, Lidarr, Bazarr, Jackett, Transmission, slskd, NordVPN, LazyLibrarian and Audiobookshelf on space-needle.

Only **Transmission and slskd** use `network_mode: service:vpn`. Everything else joins `loft-proxy` and does not go through the VPN. Apps and Caddy reach the download clients at `host.docker.internal:9091` and `:5030`.

## Configuration and storage

[.env.example](../../services/stellarr/.env.example): VPN token, `PUID`/`PGID`, timezone, Soulseek credentials. Config lives in `/opt/<product>`. Downloads mount as `/downloads`; libraries mount separately as `/movies`, `/tv`, `/music`, `/audiobooks`. slskd completes into `/mammoth/downloads/complete/lidarr`.

**Imports are copies, not hardlinks**: separate container mounts break hardlinks even on one XFS volume ([Servarr guide](https://github.com/Servarr/Wiki/blob/master/docker-guide.md)). Torrent retention is manual.

## LazyLibrarian

`https://lazylibrarian.loft.hsimah.com` (LAN only). Picks books, downloads through Transmission, imports into Audiobookshelf's library. Config at `/opt/lazylibrarian`; stop the container before editing it directly. Disable in-app auto-update.

| Setting | Value |
| --- | --- |
| Transmission host / port | `host.docker.internal` / `9091` |
| Transmission download directory | `/downloads/transmission/audiobooks` |
| Watched download directory | `/downloads/transmission/audiobooks` |
| AudioBook Library Folder | `/audiobooks` |
| Audiobook folder pattern | `$Author/$Title` |
| Keep Original Files / Keep seeding | Enabled |
| New book / audiobook / new-author statuses | `Skipped` |

Providers come from Jackett, one per indexer (not the aggregate `all` feed): take the indexer's Torznab URL, replace scheme/host/port with `http://jackett:9117`, add the Jackett API key and set Types `A`.

- AudioBook Bay (`audiobookbay`) is the audiobook indexer; set its Seeders minimum to `0` (it reports no real counts).
- TorrentLeech: Types `E` or leave it out, so it doesn't run audiobook searches.
- Provider Test only checks connectivity. If a Wanted book isn't grabbed, query `…/results/torznab/api?apikey=<key>&t=search&q=<title>` with and without `&cat=3030`.
- Jackett embeds its API key in every link; redact XML, logs and screenshots.

Mark only the chosen book **Wanted** so adding an author doesn't pull their catalogue. MP3/M4B only; no Calibre/FFmpeg mods are installed.

## Audiobookshelf

`https://audiobookshelf.loft.hsimah.com` (LAN only). Runs as Stellarr's `PUID:PGID`.

- `/opt/audiobookshelf/config` — SQLite DB; `/opt/audiobookshelf/metadata` — covers, cache, app backups.
- `/mammoth/library/audiobooks` mounted **read-only** as `/audiobooks`, so tag writing, uploads, deletes and conversion are unavailable; prepare files on the host.
- One **Audiobooks** library at `/audiobooks` with the watcher enabled. Use one listening account on every phone so progress syncs.

Manual imports: one folder per book (`Author/Title/…`). Copy into a staging dir outside the library, make it readable by `PUID:PGID`, then move it in so scans don't see partial files.

**iOS**: allow the client (Plappa works) under Settings → Privacy & Security → **Local Network**. Without it the app says "The internet connection appears to be offline" even though Safari works.

Back up both `/opt/audiobookshelf` dirs with the container stopped; its own backups sit on the same disk.

## Operations

```bash
loft-ctl rebuild stellarr
loft-ctl health stellarr
sudo docker logs stellarr-vpn --tail 50
sudo docker exec transmission curl -fsS https://ipinfo.io/ip   # must not be the home IP
```

A working UI does not prove VPN protection. Recreating the VPN container requires recreating Transmission and slskd too. Back up `/opt/{radarr,sonarr,lidarr,bazarr,jackett,transmission,slskd,lazylibrarian,audiobookshelf}` before upgrades; pin exceptions are in [upgrades](../operations/upgrades.md#rollback-and-pin-exceptions).
