# Mushr — proxy, tunnel and DNS

Mushr also has complete host overrides for
[Fjord](../../hosts/fjord/overrides/mushr/docker-compose.override.yml) (LAN proxy only)
and [Viking](../../hosts/viking/overrides/mushr/docker-compose.override.yml)
(production proxy plus opt-in `public` tunnel profile). They use separate exact
route tables and application networks; no trusted-LAN proxy routes or DNS secrets
are inherited. See the [platform runbook](../operations/application-platform.md).
The configuration described below is space-needle's retained infrastructure stack.

[Compose](../../services/mushr/docker-compose.yml) groups Caddy (`mushr`), cloudflared (`mushr-tunnel`) and dnsmasq (`mushr-dns`) on space-needle. Caddy joins `loft-proxy`; dnsmasq uses host networking and binds `192.168.86.28`.

## Configuration and boundaries

- [Caddyfile](../../services/mushr/Caddyfile) is the route table. Bridge services use container names; host listeners and VPN-published ports use `host.docker.internal`.
- [dnsmasq.conf](../../services/mushr/dnsmasq.conf) resolves `*.space-needle`, `*.loft.hsimah.com` and fleet hostnames locally. Both public Pawst domains now use its public upstream resolvers. Router DHCP should advertise this resolver. `space-needle` covers `hblake.space-needle`, although Caddy also needs a matching route.
- [.env.example](../../services/mushr/.env.example) lists LOFT_DOMAIN, Cloudflare DNS API token, tunnel token and briefing basic-auth settings. Scope the DNS token to the zones whose certificates Caddy issues.
- Public hostnames are managed separately in Cloudflare's tunnel dashboard. A Caddy route is not proof of public exposure. Keep Sputnik, n8n and briefing off that list.
- Admin listens at `127.0.0.1:8880` **inside Caddy's container**. The host publishes 80/443 only. Its Docker healthcheck probes the admin endpoint and gates tunnel startup.
- Caddy's named `caddy-data` and `caddy-config` volumes persist certificates/configuration. Do not remove them as a routine response to TLS errors.

[Dockerfile.caddy](../../services/mushr/Dockerfile.caddy) builds Caddy with the Cloudflare DNS plugin. The base version is set, but the module source is not pinned; rebuilding the same local image tag need not produce identical bytes. See [upgrade constraints](../operations/upgrades.md).

## Operations

```bash
sudo docker exec mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker exec mushr caddy reload --config /etc/caddy/Caddyfile
sudo docker exec mushr wget -qO- http://127.0.0.1:8880/config/
loft-ctl health mushr
```

Reload applies Caddyfile edits using the **running** environment. For changed `.env`, validate using Compose's environment processing, then recreate:

```bash
cd /srv/the-loft
sudo docker compose -f services/mushr/docker-compose.yml run --rm --no-deps \
  mushr caddy validate --config /etc/caddy/Caddyfile
loft-ctl rebuild mushr
loft-ctl health mushr
```

Build first when changing the image, so compilation failure does not follow a proxy shutdown. For pre-pulls, name only `mushr-tunnel mushr-dns`; the Caddy image is local and cannot be pulled from a registry.

## Briefing mount and password

The [Sputnik](sputnik.md) renderer and generated JSON are sibling read-only mounts at `/srv/briefing` and `/srv/briefing-data`. Caddy's `handle_path /data/*` joins their URL space. Preserve this layout: mounting a child beneath a read-only parent fails if the child mountpoint does not already exist.

The briefing route requires basic auth; it has no plain-HTTP counterpart. Generate the hash interactively:

```bash
sudo docker exec -it mushr caddy hash-password
```

Use a single-quoted value for a literal bcrypt hash in Compose's `.env` syntax, e.g. `BRIEFING_HASH='$2a$...'`. Existing doubled-dollar values should be checked before changing them. Compose `.env` processing differs from `docker run --env-file`; use the Compose validation command above. See [Docker interpolation rules](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/). The Homepage briefing widget needs the matching plaintext credential in Houstn's environment.

## Troubleshooting and retained incidents

- **Tunnel waiting:** inspect `sudo docker inspect mushr --format '{{json .State.Health}}'`, then Caddy validation/logs. The tunnel depends on healthy Caddy.
- **LAN resolves, container does not:** check the affected container's resolver. The repo's daemon.json explicitly uses public upstream DNS; services needing loft names have `dns: [192.168.86.28]`. Docker container-name lookup on `loft-proxy` is separate. Prefer a per-service change over restarting the entire daemon.
- **Port 53 conflict:** inspect `sudo ss -lntup` and actual bind addresses. dnsmasq's LAN listener and systemd-resolved's loopback listener can coexist. Do not disable the stub blindly; account for `/etc/resolv.conf` if changing it.
- **TLS errors:** check DNS, clock, SNI, certificate dates, Caddy logs and Cloudflare token permissions. Test with the intended hostname as shown in [triage](../../DEBUG.md). Back up certificate state before any diagnosed state repair; deleting it forces issuance and can hit rate limits.
- **Idle-browser errors:** an earlier local incident led to `protocols h1 h2` disabling HTTP/3. Preserve that workaround until deliberately retested; it is an observation about this fleet, not proof that every idle TLS failure has the same cause.
- **Registry access denied:** Caddy's local image is expected to be unpullable. For registry images, check the pinned tag and the Docker caller's registry credentials; do not dump auth configuration into shared logs.
