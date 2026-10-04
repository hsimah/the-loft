# Mushr — proxy, tunnel and DNS

On space-needle, [Compose](../../services/mushr/docker-compose.yml) runs Caddy (`mushr`, on `loft-proxy`), cloudflared (`mushr-tunnel`) and dnsmasq (`mushr-dns`, host network on `192.168.86.28`). Fjord and Viking use complete [Fjord](../../hosts/fjord/overrides/mushr/docker-compose.override.yml) and [Viking](../../hosts/viking/overrides/mushr/docker-compose.override.yml) overrides instead; see the [application platform](../operations/application-platform.md).

## Public hostnames must be first-level

**A name served through the tunnel can be at most one label below its registrable domain.** `hubbl.hsimah.com` and `clog.hsimah.com` work; `hubbl.loft.hsimah.com` cannot.

Cloudflare's free Universal SSL issues an edge certificate covering `hsimah.com` and `*.hsimah.com` — a single wildcard level. `*.loft.hsimah.com` is two levels deep and is not covered, so the edge has no certificate to present and the name fails before it ever reaches the tunnel. Covering it needs Advanced Certificate Manager, which is paid.

This is why `*.loft.hsimah.com` names are LAN-only: their certificates come from Caddy's own Let's Encrypt DNS-01 challenge, which has no such depth limit and never involves the Cloudflare edge. The loft domain is a *private* naming scheme that happens to use a public zone.

So a service reachable from outside needs: a first-level public name with its own Caddy site block, a dnsmasq entry so the LAN resolves it locally instead of hairpinning out through Cloudflare, and usually a separate `*.{$LOFT_DOMAIN}` block for LAN browsers. `hubbl` is the worked example.

Each host declares what it intends to publish in `PUBLIC_HOSTNAMES` in its `host.conf`. That is intent, not proof — the tunnel's real list lives in Cloudflare — but it gives [tests/test-caddy.sh](../../tests/test-caddy.sh) something to check:

- a declared name must be first-level, and declaring a `{$LOFT_DOMAIN}` name fails outright
- a declared name must have a Caddy route, or it 502s
- a Caddyfile must not serve a public-looking hostname that is undeclared, so exposure cannot be added without writing it down
- a space-needle public name must have a `dnsmasq` entry, or LAN clients hairpin out through Cloudflare and inherit its request-body cap

The one case no repository test can see is publishing a hostname in the Cloudflare dashboard without declaring it here. `PUBLIC_HOSTNAMES` is the inventory to reconcile against when auditing live exposure.

## Configuration

- [Caddyfile](../../services/mushr/Caddyfile): routes. Bridge services by container name; host-network and VPN ports via `host.docker.internal`.
- [dnsmasq.conf](../../services/mushr/dnsmasq.conf): resolves `*.space-needle`, `*.fjord`, `*.loft.hsimah.com` and fleet hostnames locally; everything else (including the public Pawst domains) goes upstream. Router DHCP advertises it.
- [.env.example](../../services/mushr/.env.example): `LOFT_DOMAIN`, Cloudflare DNS token (scope it to the certificate zones), tunnel token, briefing auth.
- Public hostnames are set in Cloudflare's dashboard, not here, and must be first-level (above). Each host mirrors its intended list in `PUBLIC_HOSTNAMES` in `host.conf` so it can be tested.
- A tunnel hostname pointing at an `https://` origin also needs **Origin Server Name** set to that hostname. cloudflared otherwise sends the origin's internal name (`mushr`) as SNI, Caddy has no certificate for it, and the handshake fails as a 502 with the Caddyfile looking perfect. The HTTP Host Header override is a different layer and does not substitute for it.
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
