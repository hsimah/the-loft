# Application platform: Fjord and Viking

Fjord is LAN-only dev/test; Viking is production behind a Cloudflare tunnel. Both deploy the same GitHub release artifacts. There is no Fjord→Viking SSH, copying, shared storage or runtime dependency. Space-needle stays the trusted infrastructure/DNS host.

## Compose and networking

- Base `services/<app>/docker-compose.yml` + `hosts/<role>/overrides/<app>/docker-compose.override.yml`. Requires Compose ≥ 2.24.4 for `!override`.
- The Fjord and Viking Mushr overrides replace the whole service map; they inherit nothing from space-needle's routes, DNS, plugin build, secrets or mounts.
- Each app/environment gets its own `internal: true` network (`loft-<app>-<env>`), declared internal in Mushr and external in the app. Databases go on a second app-private network Caddy does not join. No app publishes host ports.
- Mushr owns the networks: `loft-ctl start mushr <app>`, stop apps before Mushr, and prefer `up -d` for proxy changes.
- Viking Caddy listens on `127.0.0.1:8080` only; cloudflared reaches `http://mushr:8080`. Unknown Host headers get 404. Caddy is plain HTTP with no ACME here; Cloudflare terminates TLS.
- Fjord hostnames are `<app>.<dev|test>.fjord` over plain HTTP bound to `FJORD_BIND_IP`. No production data or credentials there.
- Caddy is a shared trust boundary: an app can reach other routes via Caddy, so sensitive apps still need their own auth.

Container baseline (Pawst, Caddy, cloudflared): non-root (1003; cloudflared 65532), `cap_drop: ALL`, no-new-privileges, read-only root, tmpfs, CPU/memory/PID limits, rotated logs, no Docker socket. Caddy alone adds `NET_BIND_SERVICE` because its binary carries that file capability and will not exec without it. Quote tmpfs option strings containing commas; unquoted ones pass `compose config` but fail at container creation.

## Adding an application

1. CI publishes a release archive or multi-arch OCI image and records tag, SHA-256/digest and architecture.
2. Add the shared Compose service and a Fjord override modeled on Pawst: separate dev/test service names, `/opt/<app>/<env>` data, networks and exact Caddy routes.
3. Deploy to test, then promote **the same bytes** to Viking with a production override, private network and exact Caddy route. OCI refs are `registry/app:version@sha256:<digest>`; no `build:` or `latest`. Check the image has Viking's architecture.
4. Secrets live only on the destination. Internet egress needs a dedicated egress network and firewall review, never the tunnel or `loft-proxy` network.
5. Going public is a separate step: add an exact tunnel hostname route to `http://mushr:8080` with the matching HTTP Host header and a proxied CNAME. No wildcards, Fjord names or private-network routes; keep the tunnel's catch-all 404.

For precise production rollouts use merged Compose directly (`loft-ctl update` pulls a branch and does down/up):

```bash
f="-f services/pawst/docker-compose.yml -f hosts/viking/overrides/pawst/docker-compose.override.yml"
sudo docker compose $f config --quiet
sudo docker compose $f pull
sudo docker compose $f up -d --wait
loft-ctl health pawst
```

Roll back by reverting the pin and repeating. Stateful apps also need a compatible schema or a restore.

## Network boundary

Viking's current implementation (Nest guest network + host nftables + Tailscale) is described on the [host page](../hosts/viking.md#network). On equipment that supports VLAN filtering, the target policy for host **and** Docker-forwarded traffic is:

| Order | Source → destination | Action |
|---|---|---|
| 1 | Invalid / spoofed | Drop |
| 2 | Established/related | Allow |
| 3 | Admin → Viking TCP 22 | Allow (never WAN) |
| 4 | Viking → approved DNS 53, NTP 123 | Allow exact IPs |
| 5 | Viking → trusted LAN, router management, other DMZ | Deny + log |
| 6 | Viking → Cloudflare TCP/UDP 7844 | Allow |
| 7 | Viking → public TCP 443 | Allow |
| 8 | Anything else | Deny + log |

Filter Docker traffic in `DOCKER-USER` (iptables) or a separate forward chain (nftables); UFW/INPUT rules do not cover published ports. Never flush Docker's rules. Test from the host **and** from inside each app/proxy network namespace against real open services on `192.168.86.28`, `.30` and the router, then after reboot. Only then:

```bash
sudo install -d -m 755 /etc/loft && sudo touch /etc/loft/dmz-ready
```

Remove the marker when the role changes network or hardware.

## Secrets

Outside Git on the destination only: `/etc/loft/deploy.env`, the GitHub App key, and `/etc/loft/viking-tunnel-token` (root:65532, 0640, so cloudflared can read it). Viking uses its **own** tunnel token, never space-needle's — two connectors on one tunnel route requests to the wrong origin. `COMPOSE_PROFILES=public` in Viking's `services/mushr/.env` enables the tunnel.

## Pawst on Fjord

Fjord uses state names `pawst-<dev|test>-<site>` and roots `/opt/pawst/<dev|test>/<site>` with a direct [release puller](../scripts/deploy-pull.md) call (tag plus the asset's GitHub digest). `loft-ctl deploy pawst` is Viking-only.
