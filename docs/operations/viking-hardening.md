# Viking: observed hardening and management state

Operator-reported and verified interactively on **2026-09-20**. Public Pawst
cutover is complete for **hbla.ke and hsimah.com**, including a reboot test. This record supplements the
[application platform design](application-platform.md), which also describes
stronger router/VLAN controls for replacement network equipment.

## Current topology

- Nest Wifi Pro G6ZUC supplies trusted LAN `192.168.86.0/24` and guest Wi-Fi
  `Loft DMZ`, on which Viking received `192.168.87.21/24`; gateway/DNS is
  `192.168.87.1`. This is an observed DHCP lease, not a claimed reservation.
- Viking uses NetworkManager on wlan0. `Loft DMZ` autoconnect is enabled and
  saved in `/etc/NetworkManager/system-connections/Loft DMZ.nmconnection`.
  The old trusted Wi-Fi profile and its Netplan file were deleted. Cloud-init
  is disabled via `/etc/cloud/cloud-init.disabled`; its stale `obj.pkl`,
  `network-config.json` and `/boot/firmware/network-config` were removed.
  A filename-only search found no old SSID in the checked provisioning/network
  directories. This does not claim forensic erasure of flash or backups.
  DMZ reconnection was verified after reboot. Never commit Wi-Fi secrets.
- Guest Wi-Fi has no shared devices selected. No new routed IPv6 connections are
  permitted by the host/container policy; wlan0 currently has link-local IPv6
  only. Tailscale uses its separate interface for management.
- Blanco (Fedora 44) is `100.92.100.36`; Viking (Debian 13) is
  `100.119.43.53`, tagged `tag:viking`; space-needle (Ubuntu 24.04) is
  `100.69.51.18`, tagged `tag:monitoring`.
- Blanco can reach Viking TCP 22. Space-needle can reach only Viking TCP 45876
  (Snoot/Beszel) and 61208 (Glances/Homepage). No grant permits Viking-initiated
  connections to other tailnet devices. Tailscale provides encrypted transport
  for ordinary OpenSSH, not the separate Tailscale SSH server feature. Neither
  server accepts Tailscale DNS or subnet routes; no exit/subnet routers configured.
- Public websites use Cloudflare Tunnel → Caddy → app containers.
  Tailscale is for private administration/monitoring, not public ingress.

The exact non-secret [policy and firewall files](../../hosts/viking/hardening/README.md)
are tracked. All host input/output and Docker forwarding chains default to drop.
The separate nftables tables run after the existing Docker/Tailscale filter
chains; an accept cannot override a prior drop. Bridge-to-bridge accepts defer
to Docker's network isolation rules, so those managed rules must remain enabled.
The dedicated service never flushes Docker/Tailscale tables. Docker's DNS
exceptions match its existing daemon configuration (`1.1.1.1`, `8.8.8.8`).

Host egress permits guest DNS/DHCP, public HTTPS, public UDP NTP and Tailscale
transport/discovery, after dropping private/shared/link-local/multicast targets.
Docker egress permits the two public resolvers, public HTTPS, and TCP/UDP 7844
only to the 20 global IPv4 tunnel endpoints from
[Cloudflare's firewall documentation](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-with-firewall/),
reviewed on 2026-09-20. This exception applies to egress-capable bridges, not
only to the cloudflared process; Pawst's network is internal. Public HTTPS/NTP
remain practical exceptions, not fixed per-application destination allowlists.

Host output permits TCP 8080 to `br-*` Docker bridges. Docker's userland proxy
opens a separate connection for `127.0.0.1:8080`, so the existing original-DNAT
rule alone did not allow local probes. The bridge/port exception was tested and
persisted; it does not allow container-initiated host or trusted-LAN access.

## Confirmed checks

- Key-only OpenSSH login from Blanco using `blanco_ed25519`; root login disabled,
  keyboard-interactive/password authentication disabled. Existing AllowUsers
  restricts access to adminhabl. Fresh Tailscale SSH sessions work.
- Guest attachment, SSH, firewall service and both nftables tables survive a
  reboot; Homepage and Beszel resume fresh metrics.
- Viking cannot connect to `192.168.86.28:80` or `192.168.86.250:22`, while Blanco
  can. Other attempted LAN SSH checks failed from both sides and are inconclusive.
- From a temporary unprivileged container on loft-proxy: DNS and public HTTPS
  succeed; trusted-LAN destinations, space-needle's Tailscale SSH, and the Docker
  host gateway's SSH/Glances endpoints time out. Private-egress and forwarding
  drop counters increased; input drops were consistent with host probes.
- From space-needle: Viking Glances HTTP returns 200, Beszel 45876 connects, SSH
  22 is blocked. The actual Beszel container and Homepage card work afterward.
- APT fetches all configured repositories over HTTPS. Debian security-only
  unattended upgrades are enabled; dry run succeeds. Automatic reboots are
  disabled. Docker/Tailscale/Raspberry Pi repository updates remain manual.
- Woodstock is playing Upstairs audio; Viking was removed from MA groups.
  howlr-snapclient is stopped with restart disabled. Avahi socket/service are
  disabled and inactive. Glances' own discovery is distinct from Avahi and its
  unsolicited traffic is filtered; it was not removed during this migration.
- littledog belongs only to pack-member. Only adminhabl remains in the Docker
  group. Setup now removes littledog's Docker membership for production roles.

These samples do not establish every possible destination/port as isolated.
After cutover, a probe sharing the connector's network namespace could not
connect to trusted LAN `.28:80` or `.250:22`, space-needle's Tailscale IP on
22/443, or the guest router's management ports 80/443. Both public sites and
management/monitoring survived reboot. Off-host backup/restore and explicit
forbidden IPv6 probes remain unverified. Nest guest isolation does not provide the configurable router
allowlists described by the long-term design. Host firewall root tampering,
physical interface changes and any undiscovered credential copies remain
separate risks; do not describe this as an externally enforced full VLAN DMZ.

## Caddy image capability exception

Runtime validation of caddy:2.11.4-alpine as UID 1003 with all capabilities dropped
failed before reading configuration (`operation not permitted`). Inspection found
`/usr/bin/caddy cap_net_bind_service=ep`. Validation passed after adding only
NET_BIND_SERVICE while retaining non-root identity, read-only root and
no-new-privileges. Both host overrides and CI now record this exception; Pawst and
cloudflared retain no added capabilities. The unformatted Caddyfile warning is
cosmetic, and automatic HTTPS is deliberately disabled on this private origin.

## Monitoring exception

The user explicitly retained Snoot and Glances. Viking's Houstn override contains
only Glances, regardless of COMPOSE_PROFILES; the hub cannot be started there by
accident. Preserve the existing Snoot secrets and Glances configuration. The
agents keep their current host-network/host-metrics and Docker socket mounts;
these are trusted host-level components, not confined public applications.
A `:ro` Docker socket bind is not a read-only Docker API and remains powerful.
Public app containers receive none of these mounts/namespaces or tailnet access.

The Beszel UI's existing Viking system now targets `100.119.43.53:45876` with
its existing authentication. Homepage still calls `http://viking:61208`, but the
space-needle Houstn override maps viking to that Tailscale IP. The operator
initially made this edit in the shared base Compose file on space-needle; when
adopting this checkout, revert only that equivalent base-file line and retain
the host override. Preserve any other local edits. Recreate only Homepage and
verify its card; no Beszel data migration is needed.

## Pawst cutover record

The operator downloaded these public GitHub release archives directly on Viking,
verified SHA-256 with the release puller and checked both `index.html` files:

| Site | Tag | Archive SHA-256 |
|---|---|---|
| hbla.ke | `deploy-20260717201728-ad0a0ac` | `f7348df950a41539c867c21fea5d60543f907a5652da5bf32022f69a8619235a` |
| hsimah.com | `deploy-20260719183615-503523e` | `0d02b7170c4eac6b43b92807549fed5b4c0ef688fbec086bc2fc43f0a614e906` |

Content is in `/opt/pawst/prod/{hblake,hsimah}`; state names are `pawst-hblake`
and `pawst-hsimah` under `/var/lib/loft/deploy`. These tags also match the
retained space-needle content. Viking has no latest-release polling cron.

- Caddy and Pawst run non-root with healthy checks. tmpfs YAML values containing
  commas must be quoted as a single string; unquoted flow-list values failed
  Docker container creation despite passing Compose config validation.
- Local Host probes return 200 for both sites and 404 for an unknown hostname.
- Separate tunnel `viking-prod` exposes exactly the two production hostnames,
  each to `http://mushr:8080`, with a final 404 and private routing disabled.
  Its token is `/etc/loft/viking-tunnel-token`, root:65532 mode 0640, outside Git.
  `services/mushr/.env` has `COMPOSE_PROFILES=public`, owned by adminhabl mode
  0600 so config checks can read it. No host application ports are public.
- Cellular visits appeared in Viking's Caddy logs. After removing the old
  space-needle apex DNS overrides and clearing Blanco's cache, both sites
  returned 200 via public Cloudflare addresses from the LAN too.
- Space-needle's old Pawst container is stopped with restart disabled. Its
  manifest service, content-directory provisioning, health entries and deploy
  targets are removed. The two cron files are retained in
  `/etc/loft/paused-cron/`, outside cron's active directory. No deploy was running
  when versions were checked. Old content and release records remain.
- Old Pawst Caddy routes were removed and Caddy validated/reloaded. Both site
  routes were removed from the `loft` tunnel; that tunnel remains running.
  Current DNS points to Viking. The recorded old hbla.ke CNAME target was
  `d0910264-ba87-4d29-9058-b7e4e2c373a5.cfargotunnel.com` (proxied). The operator
  identified hsimah.com as using the same named tunnel but did not record its
  exact old target separately.
- `/etc/loft/dmz-ready` exists; `loft-ctl health mushr` and `health pawst` pass.
  Both sites, fresh SSH, Homepage and Beszel were verified after reboot.

For application rollback, deploy a prior approved tag/checksum on Viking with
the existing state name. To fall back to space-needle, first restore its old
Caddy blocks, validate/reload, start its retained Pawst container and verify
both origins. Recreate the two old Cloudflare hostname routes, preserving the
current DNS until ready; then switch proxied DNS to the verified old tunnel.
Reinstate manifest/restart policy only if it will resume hosting. Resume cron
only deliberately: those jobs follow latest releases, not the rollback pin.
The host's `/tmp/Caddyfile.before-pawst-removal` is a temporary recovery copy;
retain the old reviewed Git configuration off-host for durable recovery.

## Recovery and remaining work

Root-only local archives on Viking are
`/var/backups/loft/viking-hardening-before-pawst.tar.gz` and
`/var/backups/loft/viking-hardening-after-pawst.tar.gz`. The latter contains the
final firewall files/service, SSH drop-in, unattended-upgrade policy and
cloud-init disabled marker. It excludes the tunnel token and Wi-Fi password.
Neither is an off-device backup or a tested full application restore.

The migration was committed as `aed0b3e`; Viking and space-needle checkouts
were reconciled to it. Live changes were applied manually, not by rerunning
full setup. The prior Pupyrus edit was already included in the updated baseline. Compare installed firewall files before applying
tracked copies, adapt interface/address rules for replacement hardware, and
remember that the attestation marker does not configure a router. Remaining
work includes off-host backup/restore, stale Viking LAN DNS alias cleanup,
second administrator enrollment, and live Fjord dev/test validation. Cloudflare
edge HTTP-to-HTTPS redirect policy has not been explicitly verified here.

## DNS incident after cutover

Later on 2026-09-20, both public domains stopped resolving after old tunnel-route
cleanup. The operator found the apex CNAME records missing. Viking containers
remained healthy and its local hbla.ke origin returned 200. Recreating hbla.ke's
record initially used the misspelled suffix `cfcargotunnel.com`, producing
Cloudflare HTTP 530/error 1016. Correcting the target to
`77cdbc17-f2cb-4977-88e1-1fc4337e909c.cfargotunnel.com` restored HTTP 200 through
Cloudflare; a cellular phone retry then worked. The operator also corrected
hsimah.com. DNS caches obscured the change during troubleshooting. Future route
retirement must verify both actual DNS records as well as cached HTTP probes.
See the [restore runbook](viking-restore.md) for DNS and ingress recovery checks.
