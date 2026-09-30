# The Loft project rules

Shared instructions for all coding agents; `CLAUDE.md` is a symlink to this file.

## Repository and remote hosts

This repository is the source of truth for fleet configuration, including Viking.
Start with [README.md](README.md) and the [operations index](docs/README.md), then
read the affected host's `hosts/<hostname>/host.conf`, service Compose files,
host overrides and canonical host/service runbooks before proposing changes or
asking the user about the existing setup. Follow the repository's deployment
model; an application's generic hosting guide does not override fleet conventions.

Fleet hosts are remote. Make and validate repository changes locally and provide
commands for the operator to run from `/srv/the-loft`. Do not initiate SSH or
other remote operations unless the user explicitly authorizes remote access.
A request to prepare or set up a host means preparing its repository configuration
and operator instructions unless the user says otherwise.

Keep proposed configuration distinct from verified live state. When live evidence
is needed, provide the specific operator check rather than assuming remote access.

## Working conventions

- Prefix privileged host commands (Docker, systemctl, writes under `/opt` or `/mammoth`) with `sudo`. Run `loft-ctl` as `adminhabl`, the only account on every host.
- Host manifests: `hosts/<hostname>/host.conf`. Shared Compose: `services/<name>/docker-compose.yml`. Optional overrides: `hosts/<hostname>/overrides/<service>/docker-compose.override.yml`.
- `setup.sh` provisions the host and sources optional `hosts/<hostname>/bootstrap`. `loft-ctl` provides start, stop, rebuild, health and update; shared helpers live in `control-plane/common.sh`.
- Prefer profiles in an existing service group for related fleet infrastructure. Current profiles are documented in the service pages; do not duplicate their inventory here.
- Update the canonical affected documentation when behavior changes. Review README for changes to fleet membership, service purpose or entry-point instructions. Link to config for exact tags, ports and paths instead of copying tables across pages.
- Keep docs short and current-state. Do not record rollout narratives, validation logs, superseded approaches or why something changed unless it prevents a repeat mistake; git history holds the rest. Open work goes in [plans/maintenance.md](plans/maintenance.md); delete it when done.
- Repository configuration does not prove live deployment; label unverified state briefly.

## Names

Services use single-word dog/spitz or space/aerospace wordplay: howlr (audio), pupyrus (writing), mushr (routing). The owner's pomskies, Laiko and Belki, are named after space dogs. When asked for names, offer a few from each theme with brief explanations.

Host names come from something physically visible to the owner: space-needle from the landmark; viking/fjord from a vodka bottle. Ask what is visible when proposing a host name.

Single-container services use the service name. A primary application keeps the name and helpers take prefixes (`pupyrus-db`). Bundles of independent products use product names (`radarr`, `beszel`, `ollama`); glue uses the bundle prefix (`stellarr-vpn`).
