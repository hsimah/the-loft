# Houstn — monitoring and dashboard

[Compose](../../services/houstn/docker-compose.yml) profiles: `hub` (Beszel, Uptime Kuma, Homepage) on space-needle only; `metrics` (host-network Glances on 61208) everywhere. Space-needle uses `hub,metrics`. Viking's override runs Glances only. Beszel agents are [Snoot](snoot.md).

## Configuration

- [.env.example](../../services/houstn/.env.example): profiles and `HOMEPAGE_VAR_*` widget credentials.
- Beszel: `/opt/houstn/beszel/data`. Uptime Kuma: `/opt/houstn/uptime/data` (held on 1.x).
- Homepage: [homepage-config](../../services/houstn/homepage-config), bind-mounted from the repo. Tabs `Loft` and `Briefing`; with tabs enabled every group needs a tab.
- Glances: [glances.conf](../../services/houstn/glances.conf). The space-needle override adds `/mammoth` and the remote host mappings (Viking maps to its Tailscale IP).

The Fleet row shows CPU, memory and deployed commit per host from Glances. The commit marker is written by Git hooks on checkout/merge, not by container deploys. Fjord is hidden while offline.

## Operations

```bash
loft-ctl rebuild houstn
loft-ctl health houstn
```

Missing Glances data: host's metrics profile, reachability, Homepage host mapping. Broken widget: inspect its actual API request; a healthy container doesn't mean valid credentials. The briefing widget needs the plaintext matching Mushr's hash.
