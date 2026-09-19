# Snoot — Beszel agent

[Compose](../../services/snoot/docker-compose.yml) runs a host-networked Beszel agent on each fleet host, listening on 45876 with the Docker socket mounted for container metrics. There is no service data directory; history and configured systems belong to [Houstn's](houstn.md) hub.

## Onboarding

1. In the Beszel hub, add the system and obtain the offered key/token.
2. Copy [.env.example](../../services/snoot/.env.example) to `.env` on that host. `BESZEL_KEY` is the hub SSH public key; `BESZEL_TOKEN` is a system credential. Do not blindly copy another system's token.
3. Start with `loft-ctl start snoot` and verify fresh metrics in the hub.
4. The hub's local target is `host.docker.internal:45876`, not localhost. For remote hosts use their reachable LAN address, or a hostname verified to resolve **inside the hub container**.

The hub Compose has the host-gateway mapping for its local agent. Remote names resolving on the host or in Homepage does not prove they resolve in Beszel, which has different DNS/extra-host settings. Use the LAN IP if necessary.

## Troubleshooting

```bash
sudo docker logs snoot --tail 50
sudo docker inspect snoot --format '{{json .State}}'
# From the agent host, test its own listener:
nc -zv 127.0.0.1 45876
```

From space-needle, test the remote LAN address on 45876. Check hub target, credentials and firewall before changing the image. Missing per-container metrics call for checking the socket mount and its effective permissions. The agent has no HTTP health endpoint; verify freshness through the hub.

Images use the pinned Docker Hub references in Compose. A prior GHCR pull failure is not a reason to remove version pins; inspect the tag and caller's registry credentials first.
