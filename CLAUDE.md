# The Loft project rules

- Fleet hosts are remote. Make repository changes locally; provide host commands for the operator unless remote access is explicitly authorized. Remote checkouts live at `/srv/the-loft`.
- Prefix privileged host commands (Docker, systemctl, writes under `/opt` or `/mammoth`) with `sudo`. `loft-ctl` handles its own switch to `adminhabl`.
- Host manifests: `hosts/<hostname>/host.conf`. Shared Compose: `services/<name>/docker-compose.yml`. Optional overrides: `hosts/<hostname>/overrides/<service>/docker-compose.override.yml`.
- `setup.sh` provisions the host and sources optional `hosts/<hostname>/bootstrap`. `loft-ctl` provides start, stop, rebuild, health and update; shared helpers live in `control-plane/common.sh`.
- Prefer profiles in an existing service group for related fleet infrastructure. Current profiles are documented in the service pages; do not duplicate their inventory here.
- Update the canonical affected documentation when behavior changes. Review README for changes to fleet membership, service purpose or entry-point instructions. Link to config for exact tags, ports and paths instead of copying tables across pages.
- Label proposals and historical incidents explicitly. Repository configuration does not prove live deployment. Keep observed hardware quirks and measured benchmarks; avoid turning an incident diagnosis into a universal rule.

## Names

Services use single-word dog/spitz or space/aerospace wordplay: howlr (audio), pupyrus (writing), mushr (routing). The owner's pomskies, Laiko and Belki, are named after space dogs. When asked for names, offer a few from each theme with brief explanations.

Host names come from something physically visible to the owner: space-needle from the landmark; viking/fjord from a vodka bottle. Ask what is visible when proposing a host name.

Single-container services use the service name. A primary application keeps the name and helpers take prefixes (`pupyrus-db`). Bundles of independent products use product names (`radarr`, `beszel`, `ollama`); glue uses the bundle prefix (`stellarr-vpn`).
