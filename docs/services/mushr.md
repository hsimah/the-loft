# Mushr — proxy, tunnel and DNS

On space-needle, [Compose](../../services/mushr/docker-compose.yml) runs Caddy (`mushr`, on `loft-proxy`), cloudflared (`mushr-tunnel`) and dnsmasq (`mushr-dns`, host network on `192.168.86.28`). Fjord and Viking use complete [Fjord](../../hosts/fjord/overrides/mushr/docker-compose.override.yml) and [Viking](../../hosts/viking/overrides/mushr/docker-compose.override.yml) overrides instead; see the [application platform](../operations/application-platform.md).

## Configuration

- [Caddyfile](../../services/mushr/Caddyfile): routes. Bridge services by container name; host-network and VPN ports via `host.docker.internal`.
- [dnsmasq.conf](../../services/mushr/dnsmasq.conf): resolves `*.space-needle`, `*.fjord`, `*.loft.hsimah.com` and fleet hostnames locally; everything else (including the public Pawst domains) goes upstream. Router DHCP advertises it.
- [.env.example](../../services/mushr/.env.example): `LOFT_DOMAIN`, Cloudflare DNS token (scope it to the certificate zones), tunnel token, briefing auth.
- Public hostnames are set in Cloudflare's dashboard, not here.
- Caddy's admin API is `127.0.0.1:8880` inside the container; the host publishes only 80/443. The tunnel waits for Caddy's healthcheck.
- `caddy-data`/`caddy-config` volumes hold certificates. Don't delete them to fix TLS errors; reissuing can hit rate limits.
- [Dockerfile.caddy](../../services/mushr/Dockerfile.caddy) adds the Cloudflare DNS plugin. The image is local and can't be pulled — build it before taking Caddy down.

## Operations

```bash
sudo docker exec mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker exec mushr caddy reload --config /etc/caddy/Caddyfile
loft-ctl health mushr
```

**After a Git pull, `reload` is not enough**: Caddy's bind mount still points at the replaced file. Validate the checkout in a throwaway container, then recreate Caddy (brief interruption, certificates kept). Also do this after `.env` changes:

```bash
cd /srv/the-loft
sudo docker compose -f services/mushr/docker-compose.yml run --rm --no-deps \
  mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker compose -f services/mushr/docker-compose.yml up -d --no-deps --force-recreate mushr
```

## Briefing mount and password

Sputnik's renderer and JSON are sibling read-only mounts at `/srv/briefing` and `/srv/briefing-data`, joined by `handle_path /data/*`. Keep them as siblings: a child mount under a read-only parent fails if the mountpoint doesn't exist.

```bash
sudo docker exec -it mushr caddy hash-password
```

Store the hash single-quoted in `.env` (`BRIEFING_HASH='$2a$...'`). Homepage's briefing widget needs the matching plaintext in Houstn's `.env`.

## Troubleshooting

- **Tunnel waiting**: `sudo docker inspect mushr --format '{{json .State.Health}}'`, then Caddy logs.
- **Host resolves, container doesn't**: containers use daemon.json's public DNS unless they set `dns: [192.168.86.28]`. Fix per service, not by restarting Docker.
- **Port 53 conflict**: dnsmasq on the LAN IP and systemd-resolved on loopback coexist; check `sudo ss -lntup`.
- **TLS**: check DNS, clock, SNI, cert dates, Caddy logs, token scope. Test as in [triage](../../DEBUG.md).
- **Idle-browser errors**: HTTP/3 is disabled (`protocols h1 h2`) for this; keep it until retested.
