# space-needle

Primary server: Minisforum MS-01, x86_64, wired LAN `192.168.86.28`. Named for the Seattle landmark. [host.conf](../../hosts/space-needle/host.conf) owns service membership, storage directories, release targets and URL probes.

It runs eight trusted-infrastructure service groups, including Howlr's server profile, Houstn's `hub,metrics` and Sputnik's `engine,chat,agent`. Viking hosts public web applications; Fjord's repository configuration provides dev/test environments.

## Storage and networking

`/mammoth` is an XFS volume configured on `/dev/sda1`. Confirm the device before provisioning a replacement machine; setup mounts but does not format it. Media/model weights live there, while application state generally lives under `/opt`. Exact paths are in host.conf and each Compose file. Directory provisioning ownership is not a universal application UID; see service-specific requirements.

[Mushr](../services/mushr.md) provides DNS on the LAN IP and proxy/tunnel ingress. Bridge applications join `loft-proxy`; Plex, Music Assistant, Glances, Snoot and dnsmasq use host networking. The VPN uses its own bridge namespace with published client ports. Only Transmission/slskd inherit it.

Public-upstream DNS is configured in daemon.json. Containers needing loft names use explicit service DNS or host mappings; resolution on the host does not prove resolution in every container.

## Provisioning and daily use

Follow [setup](../scripts/setup.md). Create each required environment from its example; Pawst has none. Choose the profiles above and provision service credentials through their owning pages. The [Houstn override](../../hosts/space-needle/overrides/houstn/docker-compose.override.yml) adds `/mammoth` to Glances.

```bash
cd /srv/the-loft
sudo bash setup.sh
loft-ctl health
loft-ctl update <service>
```

Pawst moved to Viking on 2026-09-20. Space-needle has no Pawst release targets
or Caddy/DNS overrides for the public sites. Its old container is stopped with
restart disabled; content and paused cron files remain for recovery. See
[Pawst](../services/pawst.md).

Service incidents are documented with their owners: [Pupyrus/database](../services/pupyrus.md), [Mushr/DNS/TLS](../services/mushr.md), [Plex/GPU](../services/pawpcorn.md), [Howlr/audio](../services/howlr.md), [Sputnik](../services/sputnik.md). Use [upgrades](../operations/upgrades.md) for backup and verification; do not duplicate those recovery procedures here.
