# Stellarr — media acquisition and audiobooks

[Compose](../../services/stellarr/docker-compose.yml) runs Radarr, Sonarr, Lidarr, Bazarr, Jackett, Transmission, slskd, NordVPN and Audiobookshelf on space-needle. Exact image pins and mounts live there.

Only **Transmission and slskd** use `network_mode: service:vpn`. NordVPN is a bridge container publishing their ports; the *arr apps join `loft-proxy` and do not route all traffic through that VPN. Radarr/Sonarr/Lidarr reach download clients through `host.docker.internal:9091` and `:5030`. Caddy uses those same host-published endpoints; the *arr UIs have no host port mappings.

## Configuration and storage

Copy [.env.example](../../services/stellarr/.env.example) for VPN token, UID/GID/timezone and Soulseek credentials. Verify UID/GID against the host and application data. VPN country/protocol and the allowed LAN range are in Compose.

Config/databases live in `/opt/<product>`. Downloads mount as `/downloads`; libraries mount separately as `/movies`, `/tv` and `/music`. slskd's configured completed path is `/downloads/complete/lidarr`, which is `/mammoth/downloads/complete/lidarr` on the host; it does not use the separately provisioned `/mammoth/downloads/soulseek` directories.

**The current separate mounts do not provide a hardlink-safe import layout.** Sharing XFS on the host is insufficient across separate container mounts. Do not assume imports consume zero extra disk. See [Servarr's Docker guide](https://github.com/Servarr/Wiki/blob/master/docker-guide.md). Any migration to a shared parent mount must also update application paths and be verified against existing libraries.

Automatic torrent deletion was removed after the operator reported that the ratio-based cleanup did not work. Stellarr setup now removes its old cron file. To disable an existing installation immediately, run on space-needle:

```bash
cd /srv/the-loft
sudo rm -f /etc/cron.d/transmission-cleanup
```

After deploying the updated Compose file, recreate only Transmission to remove the retired script mount:

```bash
sudo docker compose -f services/stellarr/docker-compose.yml up -d --no-deps transmission
```

These repository changes have not been applied to the live host. Manage torrent retention manually and verify library imports before deleting downloaded data. Import/mount verification remains tracked in [maintenance](../../plans/maintenance.md).

## Audiobookshelf

Prepared for space-needle; live deployment and phone playback are not yet verified.
Local validation on 2026-09-29 passed Compose configuration, the 54 repository
tests, documentation links and the new Caddy routes (using local TLS in the
test container). The pinned Audiobookshelf image started as UID/GID 1003 with a
read-only book mount; `/ping`, `/status` and the first-run page returned HTTP 200.
Cloudflare certificate issuance, imports and mobile playback still need the
operator checks below.

[Audiobookshelf](https://www.audiobookshelf.org/) serves manually imported books.
There is no automatic book search, download or import service. Transmission keeps
its existing VPN configuration; Audiobookshelf joins `loft-proxy` and publishes
no host port. Keep it off the public Cloudflare Tunnel hostname list.

- Open `https://audiobookshelf.loft.hsimah.com` while on the home LAN.
- Config/database: `/opt/audiobookshelf/config` (local disk).
- Metadata, covers, cache and app backups: `/opt/audiobookshelf/metadata`.
- Book files: `/mammoth/library/audiobooks`, mounted read-only as `/audiobooks`.
- The container runs as Stellarr's `PUID:PGID`; setup creates directories owned
  by `littledog:pack-member`. Verify those IDs match the existing `.env` before
  starting; do not change the existing Stellarr identity to fix one service.

### First deployment

From `/srv/the-loft` on space-needle, after pulling the reviewed branch:

```bash
id littledog
getent group pack-member
# Compare with PUID and PGID in services/stellarr/.env.
sudo rm -f /etc/cron.d/transmission-cleanup
sudo docker compose -f services/stellarr/docker-compose.yml pull audiobookshelf
sudo bash setup.sh
sudo docker exec mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker exec mushr caddy reload --config /etc/caddy/Caddyfile
loft-ctl health stellarr
```

`setup.sh` provisions the new directories, starts the configured fleet services
and removes the retired cleanup cron. It is a full host provisioning run; see
[setup side effects](../scripts/setup.md). Caddy needs the explicit reload above
because a changed bind-mounted Caddyfile does not cause Compose to restart it.
The existing LAN DNS wildcard already covers the new hostname. Homepage has an
Audiobookshelf link under Audio; refresh the dashboard after deployment.

In the web UI, create the initial administrator with a strong password, then add
an **Audiobooks** library with folder `/audiobooks`. Create a regular listening
account and use that same account on both phones so progress belongs to one user.
Set book metadata and covers to stay in the server metadata directory. The
read-only library supports playback/scanning, but writing tags into book files,
server uploads, deleting book files and in-place conversion are intentionally
unavailable. Do file preparation on the host before import.

### Manual downloads and import

Download through Transmission as usual, then copy completed books to a separate
library folder. Use one folder per book, for example:

```text
/mammoth/library/audiobooks/Author/Book Title/book.m4b
/mammoth/library/audiobooks/Author/Other Book/01.mp3
/mammoth/library/audiobooks/Author/Other Book/02.mp3
```

Preserve Transmission's download files while seeding. Copy the complete book
into a staging directory outside the library, ensure the container UID/GID can
read the files and traverse the directories, then move the finished folder into
the library and scan. This avoids scanning partially copied chapter files.
Copies consume additional space; this change does not establish hardlink imports.

### Android and iOS

Use the official Android app or an iOS client from the
[Audiobookshelf app directory](https://audiobookshelf.org/docs/documentation/community/community-apps/).
The official iOS app uses TestFlight and availability can be limited; an App Store
client from that directory is an alternative. Connect using the HTTPS URL above
and the same listening account. Download books in each app while at home for
offline playback. Mobile downloads are independent of automated server acquisition.

Verify on both phones: streaming, chapters, resume position after switching
devices, a complete offline download in airplane mode, and progress sync after
reconnecting. Cellular streaming is not configured by this change.

### Backup and verification

Back up both `/opt/audiobookshelf` directories and the audiobook library to
separate storage. Stop Audiobookshelf for a consistent filesystem copy of its
SQLite state; app-generated backups on the same disk do not cover host loss.
Use a backup made with the matching version before attempting an app downgrade.

```bash
sudo docker inspect audiobookshelf --format '{{json .State.Health}}'
sudo docker logs audiobookshelf --tail 50
curl --fail https://audiobookshelf.loft.hsimah.com/ping
```

## Upgrades and operation

```bash
loft-ctl rebuild stellarr
loft-ctl health stellarr
sudo docker logs stellarr-vpn --tail 50
sudo docker exec transmission curl -fsS https://ipinfo.io/ip
```

Compare download-container egress with the home's public IP and expected VPN exit. A reachable web UI does not prove VPN protection. When recreating the VPN namespace, recreate its dependent clients too.

Back up `/opt/{radarr,sonarr,lidarr,bazarr,jackett,transmission,slskd}` before upgrades. Preserve these exceptions:

- **VPN:** digest pinned after the `v3.12.3` tag failed authentication on 2026-07-27. Do not replace the digest with that older tag. A maintained replacement is open work.
- **Lidarr:** pinned nightly because its existing DB schema was ahead of the stable line. Do not downgrade the database by changing the tag. Verify plugin compatibility with the selected build.
- **Jackett:** Compose sets `AUTO_UPDATE=true`; confirm application self-update behavior before treating its image tag as the whole version boundary.

For client-connection errors, verify the VPN and configured client address before changing *arr networking. For slskd shares, inspect `/music` inside slskd and its read-only library mount.
