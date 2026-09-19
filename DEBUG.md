# Fleet triage

Run host commands over SSH as `adminhabl`. The checkout is `/srv/the-loft`.

```bash
loft-ctl health
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo docker logs <container> --tail 100
sudo docker inspect <container> --format '{{json .State}}'
df -h /opt /mammoth
sudo docker system df
```

`loft-ctl health` checks the active Compose services, running state and configured Docker healthchecks. URL probes check reachability only: any HTTP response passes, including 500/502, and certificate verification is disabled. A green result does not verify audio playback, application login, a working VPN, or correct content. See [health helper contract](docs/scripts/common-sh.md).

## Pick the failing layer

| Symptom | Next check |
|---|---|
| Missing/exited/restarting container | Logs and `.State`; confirm active profiles in the service `.env` |
| Exit 137 | Inspect `.State.OOMKilled`; check `free -h` and `sudo docker stats --no-stream` |
| App responds directly but proxy fails | [Mushr](docs/services/mushr.md): upstream network membership, route, DNS and Caddy logs |
| Names fail to resolve | `dig @192.168.86.28 radarr.space-needle +short`; dnsmasq listens on that LAN address |
| Permission denied | Compare the service's runtime UID/GID with the specific bind mount; do not recursively chown all service data to one user |
| New static release missing | [Deploy puller](docs/scripts/deploy-pull.md): release tag, artifact, auth and state file |
| Briefing stale or wrong | [Sputnik](docs/services/sputnik.md) and [workflow validation](services/sputnik/workflows/briefing.md) |
| Wi-Fi/audio/display issue | The relevant [host page](docs/README.md#hosts) |

For TLS testing, use the intended hostname as both HTTP host and TLS server name:

```bash
curl --resolve radarr.loft.hsimah.com:443:192.168.86.28 \
  -I https://radarr.loft.hsimah.com
sudo docker exec mushr caddy validate --config /etc/caddy/Caddyfile
sudo docker logs mushr --tail 100
```

Caddy's admin API is inside the container, not at the host's port 8880:

```bash
sudo docker exec mushr wget -qO- http://127.0.0.1:8880/config/
```

## Recovery boundaries

- `loft-ctl rebuild <service>` tears down, pulls and recreates that group. It does **not** run health checks; follow it with `loft-ctl health <service>`. `update` does both.
- Rebuilds retain declared bind mounts and named volumes. `docker compose down -v` removes named/anonymous volumes, including Caddy's certificate state; it does not delete host bind directories such as `/opt/pupyrus/db`.
- Image rollback may also require restoring an older database. See [upgrades and backups](docs/operations/upgrades.md).
- Database errors need an error-specific recovery path. See [Pupyrus](docs/services/pupyrus.md); do not use auto-upgrade as corruption recovery or delete transaction logs on inference alone.
- `setup.sh` can restart Docker, overwrite managed dotfiles and reapply ownership. It is a provisioner, not a generic repair command.

Known service incidents belong on their service pages: [Mushr](docs/services/mushr.md), [Pupyrus](docs/services/pupyrus.md), [Howlr](docs/services/howlr.md), [Stellarr](docs/services/stellarr.md), [Pawpcorn](docs/services/pawpcorn.md). Preserve rollback images when pruning Docker storage.
