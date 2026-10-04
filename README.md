# the-loft

Fleet configuration for The Loft: shared service definitions, per-host configuration and a setup/control plane. Details are in [`docs/`](docs/README.md). Provision a host with [setup.sh](docs/scripts/setup.md); operate it with [loft-ctl](docs/scripts/loft-ctl.md).

## Fleet

| Host | Hardware | Role |
|------|----------|------|
| [space-needle](docs/hosts/space-needle.md) | Minisforum MS-01 (i9, x86_64) | Trusted infrastructure, media and storage |
| [viking](docs/hosts/viking.md) | Raspberry Pi 3 B+ | Production web host (DMZ) |
| [fjord](docs/hosts/fjord.md) | Raspberry Pi 3 B+ | LAN-only dev/test |
| [calavera](docs/hosts/calavera.md) | Surface Pro 2 | Downstairs Snapcast client + touch dashboard |
| [woodstock](docs/hosts/woodstock.md) | Surface Pro (1st gen) | Upstairs Snapcast client + touch dashboard |

## Services

| Service | Host | Purpose |
|---------|------|---------|
| [clog](docs/services/clog.md) | viking | Inventory app — Nginx, PHP-FPM, SQLite |
| [houstn](docs/services/houstn.md) | all (hub on space-needle) | Observability — Beszel, Uptime Kuma, Homepage, Glances |
| [howlr](docs/services/howlr.md) | space-needle (server); calavera, woodstock (clients) | Music Assistant + Snapcast |
| [hubbl](docs/services/hubbl.md) | space-needle | Immich photo library; the only space-needle service published on the tunnel |
| [mushr](docs/services/mushr.md) | space-needle, viking, fjord | Caddy + Cloudflare Tunnel + LAN DNS |
| [pawpcorn](docs/services/pawpcorn.md) | space-needle | Plex |
| [pawst](docs/services/pawst.md) | viking (prod), fjord (dev/test) | Static sites `hbla.ke` and `hsimah.com` |
| [pupyrus](docs/services/pupyrus.md) | space-needle | WordPress + MariaDB + Redis |
| [snoot](docs/services/snoot.md) | all | Beszel agent |
| [sputnik](docs/services/sputnik.md) | space-needle | Ollama + Open WebUI + n8n; read-only Gmail/Calendar briefing |
| [stellarr](docs/services/stellarr.md) | space-needle | *arr stack, LazyLibrarian, Audiobookshelf; Transmission + slskd behind NordVPN |

## Layout

```
hosts/<hostname>/host.conf          # Per-host manifest (services, storage, health checks, public hostnames)
hosts/<hostname>/overrides/...      # Per-host compose overrides
hosts/<hostname>/bootstrap          # Optional host-specific provisioning, sourced by setup.sh
hosts/<hostname>/i3/...             # Optional i3 desktop config (when I3_ENABLED)
services/<name>/docker-compose.yml  # Shared service definition
services/<name>/.env.example        # Secret template
control-plane/                      # Shared scripts
bashrc.d inputrc.d nanorc.d tmux.d  # Dotfiles installed for adminhabl
setup.sh                            # Idempotent host provisioner
loft-ctl                            # Day-to-day control
```

Services are defined once and customized per host by Compose merge with `hosts/<hostname>/overrides/<service>/docker-compose.override.yml`. Prefer Compose profiles inside an existing service (e.g. houstn's `hub`/`metrics`) over new services.

Images are version-tagged or digest-pinned in Compose. Change the pin in Git, then `loft-ctl update <name>`. Read [upgrades](docs/operations/upgrades.md) before touching stateful services.

Fjord runs dev/test; Viking runs production. Promote the same GitHub release artifact, never a Fjord filesystem. See the [application platform](docs/operations/application-platform.md).

## CI

[validate.yml](.github/workflows/validate.yml) checks every Compose/override/profile combination, `bash -n` on scripts and manifests, JSON/Python syntax, the regression tests in `tests/`, and local doc links (`control-plane/check-docs.sh`). Caddyfiles are validated with the real binary — the space-needle one against the `Dockerfile.caddy` build, since stock Caddy rejects its Cloudflare DNS directive.

Hosts declare intended public hostnames in `PUBLIC_HOSTNAMES`; `tests/test-caddy.sh` checks they are first-level, routed and resolved locally, and that nothing publicly routable is undeclared. That is repository intent — the tunnel's live hostname list is in Cloudflare and must be reconciled separately.
