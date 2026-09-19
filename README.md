# the-loft

Fleet configuration for The Loft — a mono-repo managing all hosts with shared service definitions, per-host configuration, and a unified setup/control-plane.

For deep dives, see [`docs/`](docs/README.md).

## Fleet

| Host | Hardware | Role |
|------|----------|------|
| [space-needle](docs/hosts/space-needle.md) | Minisforum MS-01 (i9, x86_64) | Primary server — runs everything |
| [viking](docs/hosts/viking.md) | Raspberry Pi 3 B+ | Snapcast client + per-host metrics |
| [fjord](docs/hosts/fjord.md) | Raspberry Pi 3 B+ | Per-host metrics (awaiting cyberdeck repurpose) |
| [calavera](docs/hosts/calavera.md) | Surface Pro 2 (touchscreen) | Always-on Snapcast client + i3 desktop |

## Services

| Service | Purpose |
|---------|---------|
| [houstn](docs/services/houstn.md) | Fleet observability — Beszel, Uptime Kuma, Homepage, Glances |
| [howlr](docs/services/howlr.md) | Music Assistant + Snapcast — whole-home audio |
| [mushr](docs/services/mushr.md) | Caddy reverse proxy + Cloudflare Tunnel + LAN DNS |
| [pawpcorn](docs/services/pawpcorn.md) | Plex Media Server |
| [pawst](docs/services/pawst.md) | Static sites `hbla.ke` and `hsimah.com` |
| [pupyrus](docs/services/pupyrus.md) | WordPress (+ MariaDB + Redis) |
| [snoot](docs/services/snoot.md) | Beszel agent on every host |
| [sputnik](docs/services/sputnik.md) | Local LLM — Ollama + Open WebUI + n8n, read-only Gmail/Calendar assistant |
| [stellarr](docs/services/stellarr.md) | *arr stack; Transmission + slskd use NordVPN |

## Image pinning

Compose image references are version-tagged or digest-qualified; exact references live in each service's compose file. Change the selected pin in Git, then deploy that service with `loft-ctl update <name>`.

Read [upgrades and backups](docs/operations/upgrades.md) before changing stateful services. A manifest revert does not undo database migrations, cached images may have been pruned, and Caddy's local build has an unversioned plugin dependency. The guide also records the VPN, Snapclient, Lidarr and database pin exceptions.

## How it's organized

```
hosts/<hostname>/host.conf          # Per-host manifest (services, storage, health checks)
hosts/<hostname>/overrides/...      # Per-host compose overrides
hosts/<hostname>/bootstrap          # Optional host-specific provisioning, sourced by setup.sh if present
hosts/<hostname>/i3/...             # Optional i3 desktop config (deployed by setup.sh when I3_ENABLED)
services/<name>/docker-compose.yml  # Shared service definition
services/<name>/.env.example        # Secret template
control-plane/                      # Shared scripts (common.sh, deploy-pull.sh, ...)
bashrc.d inputrc.d nanorc.d tmux.d  # Shared dotfiles, installed for adminhabl by setup.sh
setup.sh                            # Idempotent host provisioner
loft-ctl                            # Day-to-day fleet control
```

Services are defined once and customized per host via Docker Compose's native merge from `hosts/<hostname>/overrides/<service>/docker-compose.override.yml`. Fleet-wide containers prefer Compose **profiles** inside an existing service (e.g. `houstn`'s `hub` / `metrics`) over standalone services.

## Scripts

| Script | Purpose |
|--------|---------|
| [setup.sh](docs/scripts/setup.md) | Provisions a host from `hosts/$(hostname)/host.conf` |
| [loft-ctl](docs/scripts/loft-ctl.md) | start / stop / rebuild / health / update |
| [deploy-pull.sh](docs/scripts/deploy-pull.md) | Hourly GitHub Release puller for static-site deploys |
| [github-app-token.sh](docs/scripts/github-app-token.md) | GitHub App installation tokens for private-repo pulls |
| [common.sh](docs/scripts/common-sh.md) | Sourced library — compose-arg resolution + health checks |

## Quick start

```bash
# Run as adminhabl with GitHub access configured
sudo install -d -o adminhabl -g adminhabl /srv/the-loft
git clone git@github.com:hsimah-services/the-loft.git /srv/the-loft
cd /srv/the-loft

# Copy .env.example → .env for each service this host runs
# (see hosts/<hostname>/host.conf for the SERVICES list, and the
#  per-host docs page for which .env files matter)

sudo bash setup.sh
```

Day-to-day after that is `loft-ctl` — see [`docs/scripts/loft-ctl.md`](docs/scripts/loft-ctl.md).

For a fresh host, see the host-specific docs page and [`docs/scripts/setup.md`](docs/scripts/setup.md).

## Security model

- **SSH**: Only `adminhabl` can SSH in. Password auth disabled on Pis.
- **Container identity**: Setup creates new `littledog`/`pack-member` accounts as UID/GID 1003, preserving existing IDs. Containers use image defaults or service-specific user settings; verify each application’s data ownership instead of applying one UID fleet-wide.
- **Admin escalation**: You log in as `adminhabl` and use `sudo` for privileged actions; `loft-ctl` still auto-elevates to `adminhabl` via `su` if invoked by another user.
- **External access**: Pawst uses an outbound Cloudflare Tunnel. Public hostnames are managed in the Cloudflare dashboard; repository routes alone do not prove exposure. Keep Sputnik, n8n and briefing off the public hostname list. Plex Remote Access and router state require separate live verification.
- **Unauthenticated services**: `ollama` has no auth of any kind — anything that reaches port 11434 can run inference and pull or delete models. It is published on `127.0.0.1` only and deliberately has no Caddy route.
- **Static content with no app behind it**: `briefing.loft.hsimah.com` serves sputnik's inbox digest straight off disk, so there is no application login to rely on — the Caddy route carries `basic_auth` (`BRIEFING_*` in `services/mushr/.env`) and, like `n8n`, stays off the tunnel's public-hostname list.
- **i3 desktop** (calavera): lightdm autologs the `rodnik` service account into an i3 session that auto-launches `firefox --kiosk` fullscreen as a Music Assistant touch dashboard (config in `hosts/calavera/i3/`, URL + HiDPI scaling from `host.conf`); `rodnik` has no sudo or docker.

## Debugging

See [DEBUG.md](DEBUG.md) for short triage steps, then the relevant service or host page. Proposed work and required live checks are in [maintenance](plans/maintenance.md). Historical plans are in [the archive](docs/archive/README.md).

## CI

A GitHub Actions workflow (`.github/workflows/validate.yml`) validates every push:

- All compose + override combinations pass `docker compose config --quiet`
- Howlr validated under both `COMPOSE_PROFILES=server` and `=client`
- Sputnik validated under `engine`, `chat`, `agent`, and all three combined
- Houstn validated under `hub`, `metrics`, and both combined
- Shell scripts, bootstrap/hooks and `host.conf` files pass `bash -n`
- Health-helper regression tests and active-document link/anchor checks run without remote access
- JSON configuration and Python syntax are checked
