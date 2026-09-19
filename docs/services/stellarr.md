# Stellarr — media acquisition

[Compose](../../services/stellarr/docker-compose.yml) runs Radarr, Sonarr, Lidarr, Bazarr, Jackett, Transmission, slskd and NordVPN on space-needle. Exact image pins and mounts live there.

Only **Transmission and slskd** use `network_mode: service:vpn`. NordVPN is a bridge container publishing their ports; the *arr apps join `loft-proxy` and do not route all traffic through that VPN. Radarr/Sonarr/Lidarr reach download clients through `host.docker.internal:9091` and `:5030`. Caddy uses those same host-published endpoints; the *arr UIs have no host port mappings.

## Configuration and storage

Copy [.env.example](../../services/stellarr/.env.example) for VPN token, UID/GID/timezone and Soulseek credentials. Verify UID/GID against the host and application data. VPN country/protocol and the allowed LAN range are in Compose.

Config/databases live in `/opt/<product>`. Downloads mount as `/downloads`; libraries mount separately as `/movies`, `/tv` and `/music`. slskd's configured completed path is `/downloads/complete/lidarr`, which is `/mammoth/downloads/complete/lidarr` on the host; it does not use the separately provisioned `/mammoth/downloads/soulseek` directories.

**The current separate mounts do not provide a hardlink-safe import layout.** Sharing XFS on the host is insufficient across separate container mounts. Do not assume imports consume zero extra disk. See [Servarr's Docker guide](https://github.com/Servarr/Wiki/blob/master/docker-guide.md). Any migration to a shared parent mount must also update application paths and be verified against existing libraries.

[The cleanup script](../../services/stellarr/transmission/remove-torrents.sh), installed by service setup as a midnight cron, removes torrents and data at ratio ≥2. It does **not** verify successful import. Check library copies and import queues before manually invoking it or relying on its safety. Mount/cleanup remediation remains tracked in [maintenance](../../plans/maintenance.md).

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

For client-connection errors, verify the VPN and configured client address before changing *arr networking. For slskd shares, inspect `/music` inside slskd and its read-only library mount. The ratio script parses human-readable Transmission output (`ratio=$9`); verify that format after client upgrades.
