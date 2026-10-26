# Kennl — forge and CI

[Compose](../../services/kennl/docker-compose.yml) has two profiles. `forge` runs Forgejo (`forgejo`) and its Postgres (`kennl-db`) on [space-needle](../hosts/space-needle.md). `runner` runs the Actions runner (`forgejo-runner`) and the Docker daemon jobs run in (`kennl-dind`) on [helarctos](../hosts/helarctos.md). Each host sets its profile as `COMPOSE_PROFILES` in kennl's `.env`. The name: the kennel where the pack's code lives. Plan: [#150](https://github.com/hsimah/the-loft/issues/150), [#151](https://github.com/hsimah/the-loft/issues/151).

Forgejo becomes the source of truth for repositories, issues and PRs. GitHub copies become read-only push mirrors.

| Host | Path | Contents |
|---|---|---|
| space-needle | `/opt/kennl/forgejo/data` | Repositories, attachments, packages, SSH host keys |
| space-needle | `/opt/kennl/forgejo/config` | `app.ini`, including generated secrets |
| space-needle | `/opt/kennl/db` | Postgres |
| helarctos | `/opt/kennl/runner` | Actions cache |

Nightly to Google Drive: a `forgejo dump`, a `pg_dump` and `app.ini` in the open restic repository ([backups](../operations/backups.md); configured, not yet run against Drive). Once GitHub is only a mirror, kennl holds the only copy of issues and PRs.

## Access

- Web and HTTPS git: `https://kennl.loft.hsimah.com`, through space-needle's Caddy to `forgejo:3000` on `loft-proxy`. LAN and Tailscale only; never add it to the tunnel.
- SSH git: `ssh://git@kennl.loft.hsimah.com:2222/...` (space-needle).
- Sign-up is disabled, and every page requires sign-in.

## Runner isolation

- Jobs run unprivileged inside `kennl-dind`, on a fresh network per job, with no volumes and no Docker socket ([runner.yml](../../services/kennl/runner.yml)).
- The runner reaches `kennl-dind` over TLS and holds only the client certificate. Job containers cannot reach that API.
- `kennl-dind` is privileged. A container escape from a job reaches helarctos, so the boundary is unprivileged jobs plus a protected default branch, not the dind container.
- The runner and jobs reach Forgejo by its public name, through Mushr's DNS (`192.168.86.28`) and Caddy.
- **Egress:** the runner and `kennl-dind` sit alone on the `kennl-jobs` bridge. helarctos's [firewall](../../hosts/helarctos/kennl-egress.nft), installed by its bootstrap, lets that bridge reach Mushr DNS, space-needle `:443`, llama-swap `:8080` and the internet on ports 80 and 443. It blocks the rest of the LAN, Tailscale and helarctos itself. Space-needle `:443` is every Caddy site, not only Forgejo; a per-hostname allowlist through a proxy is open work in #151.
- Check from a container on dind's network, which leaves the same way jobs do:

  ```bash
  sudo docker exec kennl-dind docker run --rm alpine:3.22 sh -c 'nc -zw3 192.168.86.21 8080 && echo llama-swap ok; nc -zw3 192.168.86.28 22 || echo space-needle ssh blocked'
  ```

## Setup

Compose checks every variable in the file on both hosts, so each `.env` keeps all the example's lines, including blank ones.

1. space-needle: copy [.env.example](../../services/kennl/.env.example), set `COMPOSE_PROFILES=forge` and generate `DB_PASSWORD` with `openssl rand -hex 32` **before** the first start. Then `loft-ctl start kennl`.
2. Create the admin:

   ```bash
   sudo docker exec -it forgejo forgejo admin user create --admin --username hsimah --email <email> --random-password
   ```

3. Site Administration → Actions → Runners → Create new runner gives a UUID and a token. The UUID goes in `server.connections` in [runner.yml](../../services/kennl/runner.yml) (commit it). `forgejo-runner register` is deprecated and rejects this token.
4. helarctos: copy the example, set `COMPOSE_PROFILES=runner` and `RUNNER_TOKEN`, then pull and start. After a later `runner.yml` change, recreate the runner: it is a file bind mount, so the runner keeps the old file otherwise.

   ```bash
   sudo docker compose -f services/kennl/docker-compose.yml up -d --no-deps --force-recreate runner
   ```

5. Migrate a repository from GitHub (New Migration → GitHub, not a mirror, so issues come too). Turn off Actions (Settings → Units → Overview) until its workflows are ported; Forgejo otherwise runs `.github/workflows`, recursively, so any `.yml` in a subfolder there is parsed as a workflow too. Jobs have no Docker, so steps that run `docker compose` fail. At cutover, add a push mirror back to GitHub under Settings → Repository → Mirror settings. Push mirrors copy git refs only. Releases need their own upload step for Viking.

## Upgrades

Forgejo migrates its schema on upgrade and cannot go back. Stay on the LTS line, dump first, and read the [upgrades](../operations/upgrades.md) runbook. Regenerate the runner config from the new runner image and diff it against `runner.yml`.
