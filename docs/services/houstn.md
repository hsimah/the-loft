# Houstn — monitoring and dashboard

[Compose](../../services/houstn/docker-compose.yml) uses `hub` for Beszel, Uptime Kuma and Homepage on space-needle, and `metrics` for host-networked Glances on every host. space-needle uses `COMPOSE_PROFILES=hub,metrics`; other hosts use `metrics`. [Snoot](snoot.md) documents Beszel agent onboarding.

## Configuration and data

Copy [.env.example](../../services/houstn/.env.example). Hub widget credentials come from each application's UI and are referenced through `HOMEPAGE_VAR_*` placeholders. The environment also selects profiles, including on metrics-only hosts.

- Beszel state: `/opt/houstn/beszel/data`.
- Uptime Kuma state: `/opt/houstn/uptime/data`; keep a backup before any major migration. The current pin is deliberately on 1.x.
- Homepage config: [homepage-config](../../services/houstn/homepage-config), bind-mounted from the repo. `services.yaml` defines links/widgets; `settings.yaml` defines layout/tabs; `widgets.yaml` is the top bar; `docker.yaml` selects the Docker socket.
- Glances: [glances.conf](../../services/houstn/glances.conf), host network and port 61208. The [space-needle override](../../hosts/space-needle/overrides/houstn/docker-compose.override.yml) adds the media-volume mount.

Homepage's Fleet row includes space-needle, Viking, Calavera and Woodstock,
with CPU, memory and deployed-commit widgets from Glances. Fjord remains
hidden while offline. The space-needle host override supplies the remote host
mappings; update them if LAN addresses change. Containers resolving loft domain names need the configured LAN DNS server. Beszel connectivity is separate from whether Homepage can resolve a host.

## Operations

```bash
loft-ctl rebuild houstn
loft-ctl health houstn
```

Use Uptime Kuma's UI to configure monitors and its status-page slug for Homepage. A missing API key should be repaired in `.env`, followed by recreation. Inspect a widget's actual API request when debugging rather than assuming a healthy container means valid widget credentials.

The `Loft` tab contains fleet services; `Briefing` contains Sputnik's digest and assistant links. Every layout group must have a tab when tabs are enabled. The briefing widget needs the plaintext credential matching Mushr's bcrypt hash; it reads counts/freshness, not the complete report.

For missing Glances data, check the host's metrics profile, network reachability and the Homepage host mapping. For missing `/mammoth`, check the host override and widget disk selection. The deployed-version marker is written by checkout/merge hooks; it is a checkout indicator, not a container-version inventory.
