# Operations index

Start with the [fleet overview](../README.md). Exact images, ports and mounts live in the manifests linked from each page.

## Hosts

- [space-needle](hosts/space-needle.md) — primary server and storage
- [viking](hosts/viking.md) — production web host (Pawst, Clog)
- [fjord](hosts/fjord.md) — LAN-only dev/test and Bluetooth audio
- [calavera](hosts/calavera.md) — Downstairs audio and touch dashboard
- [woodstock](hosts/woodstock.md) — Upstairs audio and touch dashboard
- [helarctos](hosts/helarctos.md) — CI runner and GPU inference

## Services

- [Clog](services/clog.md) — inventory app on Viking
- [Houstn](services/houstn.md) — dashboards and Glances
- [Howlr](services/howlr.md) — Music Assistant and Snapcast
- [Hubbl](services/hubbl.md) — Immich photo library
- [Kennl](services/kennl.md) — Forgejo forge and CI runner
- [Mercurius](services/mercurius.md) — household wiki and documents (encrypted)
- [Mushr](services/mushr.md) — proxy, tunnel and LAN DNS
- [Pawpcorn](services/pawpcorn.md) — Plex
- [Pawst](services/pawst.md) — blog
- [Snoot](services/snoot.md) — Beszel agents
- [Sputnik](services/sputnik.md) — Open WebUI, n8n and llama-swap
- [Stellarr](services/stellarr.md) — media acquisition and audiobooks

## Runbooks and scripts

- [Triage](../DEBUG.md)
- [Application platform](operations/application-platform.md) — Fjord/Viking conventions, promotion, network policy
- [Viking restore](operations/viking-restore.md)
- [OneDrive → Hubbl migration](operations/onedrive-migration.md) — temporary; delete when done
- [Upgrades and backups](operations/upgrades.md)
- [Off-site backups](operations/backups.md) — restic to Google Drive; built, shelved
- [setup.sh](scripts/setup.md), [loft-ctl](scripts/loft-ctl.md), [health helpers](scripts/common-sh.md)
- [Release puller](scripts/deploy-pull.md), [GitHub App tokens](scripts/github-app-token.md), [image update check](scripts/image-updates.md)
- [Open work](../plans/maintenance.md)
- [Automation plans](automation/README.md) — household AI services: plans and open work
