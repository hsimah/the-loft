# Snoot — Beszel agent

[Compose](../../services/snoot/docker-compose.yml) runs a host-network Beszel agent on every host (port 45876, Docker socket mounted). History lives in [Houstn's](houstn.md) hub.

## Onboarding

1. Add the system in the Beszel hub and copy its key and token.
2. Copy [.env.example](../../services/snoot/.env.example) to `.env`: `BESZEL_KEY` is the hub's public key, `BESZEL_TOKEN` is per system — never reuse another host's.
3. `loft-ctl start snoot`, then confirm fresh metrics in the hub.

Hub targets: space-needle is `host.docker.internal:45876`; others use their LAN IP (Viking: Tailscale IP). Names that resolve on the host or in Homepage may not resolve inside the Beszel container.

## Troubleshooting

```bash
sudo docker logs snoot --tail 50
nc -zv 127.0.0.1 45876
```

Then test the host's address on 45876 from space-needle. No HTTP health endpoint; check freshness in the hub.
