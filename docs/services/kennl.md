# Kennl — forge and CI

[Compose](../../services/kennl/docker-compose.yml) runs Forgejo (`forgejo`), its Postgres (`kennl-db`), the Actions runner (`forgejo-runner`) and the Docker daemon jobs run in (`kennl-dind`) on [helarctos](../hosts/helarctos.md). The name: the kennel where the pack's code lives. Running, with the runner connected. Plan: [#150](https://github.com/hsimah/the-loft/issues/150), [#151](https://github.com/hsimah/the-loft/issues/151).

Forgejo becomes the source of truth for repositories, issues and PRs. GitHub copies become read-only push mirrors.

| Host path | Contents |
|---|---|
| `/opt/kennl/forgejo/data` | Repositories, attachments, packages, SSH host keys |
| `/opt/kennl/forgejo/config` | `app.ini`, including generated secrets |
| `/opt/kennl/db` | Postgres |
| `/opt/kennl/runner` | Runner registration (`.runner`) and Actions cache |

Back up a `forgejo dump` plus `pg_dump`, together with `app.ini`. Once GitHub is only a mirror, kennl holds the only copy of issues and PRs.

## Access

- Web and HTTPS git: `https://kennl.loft.hsimah.com`, through space-needle's Caddy to helarctos `:3000`. LAN and Tailscale only; never add it to the tunnel.
- SSH git: `helarctos:2222`.
- Sign-up is disabled, and every page requires sign-in.

## Runner isolation

- Jobs run unprivileged inside `kennl-dind`, on a fresh network per job, with no volumes and no Docker socket ([runner.yml](../../services/kennl/runner.yml)).
- The runner reaches `kennl-dind` over TLS and holds only the client certificate. Job containers cannot reach that API.
- `kennl-dind` is privileged. A container escape from a job reaches the host, so the boundary is unprivileged jobs plus a protected default branch, not the dind container.
- Jobs resolve names through Mushr (`192.168.86.28`). Egress filtering is open work in #151.

## Setup

1. Copy [.env.example](../../services/kennl/.env.example). Generate `DB_PASSWORD` with `openssl rand -hex 32` **before** the first start.
2. `sudo loft-ctl start kennl`. The runner restarts until it is connected (step 4).
3. Create the admin:

   ```bash
   sudo docker exec -it forgejo forgejo admin user create --admin --username hsimah --email <email> --random-password
   ```

4. Connect the runner. Site Administration → Actions → Runners → Create new runner gives a UUID and a token. The UUID goes in `server.connections` in [runner.yml](../../services/kennl/runner.yml) (commit it). The token goes in `.env` as `RUNNER_TOKEN`. `forgejo-runner register` is deprecated and rejects this token. Then:

   ```bash
   git pull
   # runner.yml is a file bind mount: recreate, or the runner keeps the old file.
   sudo docker compose -f services/kennl/docker-compose.yml up -d --no-deps --force-recreate runner
   ```

5. Migrate a repository from GitHub (New Migration → GitHub), then add a push mirror back to it under Settings → Repository → Mirror settings. Push mirrors copy git refs only. Releases need their own upload step for Viking.

## Upgrades

Forgejo migrates its schema on upgrade and cannot go back. Stay on the LTS line, dump first, and read the [upgrades](../operations/upgrades.md) runbook. Regenerate the runner config from the new runner image and diff it against `runner.yml`.
