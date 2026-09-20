# Operations index

Start with the [fleet overview](../README.md). Exact service membership, image tags, mounts and endpoints live in the manifests linked from each page.

## Hosts

- [space-needle](hosts/space-needle.md) — primary server and storage
- [viking](hosts/viking.md) — Upstairs audio client
- [fjord](hosts/fjord.md) — metrics only; cyberdeck proposal
- [calavera](hosts/calavera.md) — Downstairs audio and touch dashboard
- [woodstock](hosts/woodstock.md) — original Surface Pro; Debian installed, fleet provisioning pending

## Services

- [Houstn](services/houstn.md) — dashboards and Glances
- [Snoot](services/snoot.md) — Beszel agents
- [Howlr](services/howlr.md) — Music Assistant and Snapcast
- [Mushr](services/mushr.md) — proxy, tunnel and LAN DNS
- [Pawpcorn](services/pawpcorn.md) — Plex
- [Stellarr](services/stellarr.md) — media acquisition; Transmission/slskd use the VPN
- [Pupyrus](services/pupyrus.md) — WordPress, MariaDB and Redis
- [Pawst](services/pawst.md) — static sites
- [Sputnik](services/sputnik.md) — local inference, chat and briefing workflow

## Runbooks and scripts

- [Triage](../DEBUG.md)
- [Pi provisioning](operations/raspberry-pi.md)
- [Calavera reimage](operations/calavera-reimage.md)
- [Upgrades and backups](operations/upgrades.md)
- [Setup](scripts/setup.md), [loft-ctl](scripts/loft-ctl.md), [shared health helpers](scripts/common-sh.md)
- [Release deployment](scripts/deploy-pull.md), [GitHub App authentication](scripts/github-app-token.md)
- [Open maintenance work](../plans/maintenance.md)

Historical migration plans live in [archive](archive/README.md). The [September notes audit](audits/2026-09-19-notes.md) records the cleanup baseline; its old line numbers and quoted instructions are historical evidence.
