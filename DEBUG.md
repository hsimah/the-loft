# Fleet triage

Run on the host as `adminhabl` from `/srv/the-loft`.

```bash
loft-ctl health
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo docker logs <container> --tail 100
sudo docker inspect <container> --format '{{json .State}}'
df -h /opt /mammoth
```

`loft-ctl health` checks container state/healthchecks plus URL reachability. Any HTTP response passes (including 500/502) and TLS is not verified, so green does not prove playback, login, VPN or content. See [health helpers](docs/scripts/common-sh.md).

| Symptom | Next check |
|---|---|
| Missing/exited/restarting container | Logs and `.State`; active profiles in the service `.env` |
| Exit 137 | `.State.OOMKilled`, `free -h`, `sudo docker stats --no-stream` |
| App works directly, proxy fails | [Mushr](docs/services/mushr.md): network membership, route, DNS, Caddy logs |
| Names fail to resolve | `dig @192.168.86.28 radarr.space-needle +short` |
| Permission denied | Compare the container's UID/GID with that bind mount; never recursively chown all data |
| New static release missing | [Release puller](docs/scripts/deploy-pull.md) |
| Briefing stale | [Sputnik](docs/services/sputnik.md) |
| Wi-Fi/audio/display | The [host page](docs/README.md#hosts) |

TLS test with the real hostname as both Host and SNI:

```bash
curl --resolve radarr.loft.hsimah.com:443:192.168.86.28 -I https://radarr.loft.hsimah.com
sudo docker exec mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker exec mushr wget -qO- http://127.0.0.1:8880/config/   # admin API is inside the container
```

## Recovery boundaries

- `loft-ctl rebuild` does down/pull/up but **no** health check; `update` does both.
- `docker compose down -v` deletes named volumes, including Caddy's certificates. Bind mounts survive.
- Image rollback may also need the matching database backup; see [upgrades](docs/operations/upgrades.md).
- `setup.sh` restarts Docker, overwrites dotfiles and reapplies ownership. It is a provisioner, not a repair tool.
- Keep rollback images when pruning Docker storage.
