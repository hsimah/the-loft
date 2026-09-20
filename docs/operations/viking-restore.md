# Restore the Viking production role

Viking is a role, not a particular Raspberry Pi. Use this runbook on supported
Debian/Ubuntu replacement hardware with hostname `viking`. Adapt the tracked
firewall's `wlan0`, guest gateway and Tailscale addresses before applying it.
The [live record](viking-hardening.md) describes the tested original host; this
restore workflow has automated checks but has not had a full bare-metal drill.

[hosts/viking/restore](../../hosts/viking/restore) recovers Pawst content through
the existing release puller and starts only the local proxy/application. Its
[pinned release manifest](../../hosts/viking/releases.json) records approved
artifacts. Update it with each production release so recovery does not silently
return to the first cutover versions. Runtime image versions remain in Compose.

## Recovery material

Keep an encrypted off-device copy of:

- The reviewed repository commit and approved release archives/checksums; public
  GitHub availability is not an off-device backup or an artifact-retention guarantee.
- `/etc/loft` secrets, the actual firewall files and service unit, SSH/update
  policy, and the admin public key. Keep private keys out of Git.
- Ignored service environments, especially `services/snoot/.env` and
  `services/mushr/.env`; Glances configuration and any bespoke monitoring secrets.
- `/opt/pawst/prod` and `/var/lib/loft/deploy` as recovery copies. The script
  re-fetches verified artifacts even when restored state markers match.
- Cloudflare tunnel identity/routes, proxied DNS targets, and Tailscale grants.
  Keep Wi-Fi credentials separately from ordinary configuration archives.

The two local hardening tarballs recorded in the live runbook exclude the
Cloudflare token and Wi-Fi password. They are not complete recovery backups.
Re-enroll replacement devices in Tailscale rather than running cloned node keys
concurrently. Update central grants, input rules and Homepage/Beszel mappings
if addresses change. Do not run two active public connectors unintentionally.

## 1. Establish host access and the network boundary

Install the minimal OS, updates, NetworkManager and key-authenticated adminhabl
access. Connect only to the isolated network. Establish Tailscale management
from Blanco and monitoring from space-needle using the tracked grants. Disable
password/root SSH only after verifying a fresh key login. Remove old trusted
Wi-Fi credentials from active profiles and provisioning caches. Disable completed
cloud-init provisioning via `/etc/cloud/cloud-init.disabled` when NetworkManager
has a persistent working DMZ profile. Do not erase provisioning data blindly on
a differently provisioned replacement.

Review the [network policy](application-platform.md#required-network-boundary-operator-gate)
and [hardening baseline](../../hosts/viking/hardening/README.md). The Nest guest
network is not a configurable VLAN firewall. Set the required external boundary
before public exposure; no inbound router port forwarding is needed.

## 2. Install the reviewed hardening configuration

Clone `https://github.com/hsimah/the-loft.git` to `/srv/the-loft` and select the
reviewed commit. Inspect files before installation, especially interface/IP
assumptions. Install `nftables`, `unattended-upgrades` and prerequisites using
HTTPS package repositories. Install Tailscale from its official repository;
restore its management policy before loading restrictive firewall rules.

On a replacement with the same reviewed addresses/interfaces:

```bash
cd /srv/the-loft
sudo install -d -m 0755 /etc/loft /etc/ssh/sshd_config.d
sudo install -m 0644 hosts/viking/hardening/firewall*.nft /etc/loft/
sudo install -m 0644 hosts/viking/hardening/loft-firewall.service /etc/systemd/system/
sudo install -m 0644 hosts/viking/hardening/00-loft-hardening.conf /etc/ssh/sshd_config.d/
sudo install -m 0644 hosts/viking/hardening/52loft-unattended-upgrades /etc/apt/apt.conf.d/
sudo nft --check --file /etc/loft/firewall.nft
sudo sshd -t
```

Use console access or a timed firewall rollback before enabling the service.
Do not flush Docker/Tailscale tables. After validation, reload SSH, run
`sudo systemctl daemon-reload` and enable `loft-firewall.service`. Configure
`APT::Periodic::Update-Package-Lists "1"` and
`APT::Periodic::Unattended-Upgrade "1"` in APT configuration, enable
`apt-daily.timer`/`apt-daily-upgrade.timer`, and dry-run unattended upgrades.
Disable Avahi/socket and retire any Snapclient deployment. NTP must synchronize
through the allowed public UDP 123 path. Verify effective SSH configuration,
fresh Tailscale access, monitoring, positive public HTTPS and negative trusted
LAN probes before creating `/etc/loft/dmz-ready`. That file is a new operator
attestation; do not treat a restored copy as proof the new network is secured.

## 3. Provision without public ingress

Install monitoring secrets from the encrypted backup. Keep the public tunnel
profile disabled during recovery, including when a saved `.env` enables it:

```bash
sudo env COMPOSE_PROFILES= bash /srv/the-loft/setup.sh
```

Setup creates the service account/directories, Docker/logging/DNS configuration,
metrics services, and host overrides. Empty Pawst content may initially fail
health checks. Setup does not install or verify the firewall by itself.
Inspect any setup warnings and verify littledog has UID/GID 1003, no Docker or
old audio membership, and adminhabl retains management access.

For recovery on an already configured machine, explicitly stop the public
connector and Pawst before restoring (this interrupts service on that host):

```bash
sudo docker stop mushr-tunnel pawst
```

If these containers do not exist on a fresh host, no stop is needed. The restore
script refuses to apply while either is running. Monitoring and Tailscale remain
up. Do not run another deployment concurrently.

## 4. Restore pinned content and check local routing

```bash
cd /srv/the-loft
hosts/viking/restore --plan
sudo hosts/viking/restore --apply
```

Default/`--plan` prints commands without contacting GitHub or changing the host.
`--apply` checks hostname, root, attestation, active firewall/tables, UID/GID,
Docker and Compose; backs up old release markers under `/var/backups/loft`;
then forces a verified re-fetch using the puller's normal lock. It starts only
Mushr and Pawst, waits for health and checks both sites plus unknown-host 404.
It does not start cloudflared, restore secrets, alter the router or install
firewall rules. Partial recovery can leave one site updated; keep ingress
stopped, correct the problem and rerun. The sync is not atomic.

The script needs GitHub access. If releases have disappeared, recover preserved
archives/content through the separately tested backup procedure; do not replace
a pin with `latest` to get past a failed download.

## 5. Deliberately enable production ingress

Restore or issue the chosen tunnel token as `/etc/loft/viking-tunnel-token`,
root:65532 mode 0640. For a parallel replacement use a separate tunnel until
cutover; keep its hostname/DNS routes private until tests pass. Install the
ignored `services/mushr/.env` with `COMPOSE_PROFILES=public`, readable only by
adminhabl/root. Check actual Cloudflare endpoint requirements against the
tracked TCP/UDP 7844 list before starting:

```bash
sudo docker compose \
  -f /srv/the-loft/services/mushr/docker-compose.yml \
  -f /srv/the-loft/hosts/viking/overrides/mushr/docker-compose.override.yml \
  --profile public up -d mushr-tunnel
```

The current Viking tunnel target recorded during recovery is
`77cdbc17-f2cb-4977-88e1-1fc4337e909c.cfargotunnel.com`. Verify the Tunnel ID
in Cloudflare rather than copying a connector ID or reusing this target for a
new tunnel. Each zone needs a proxied apex CNAME to the chosen tunnel target.
The suffix is **cfargotunnel.com**, not `cfcargotunnel.com`.

Deleting old tunnel hostname routes during this cutover was followed by missing
apex DNS records for both sites. Recheck the actual records after route cleanup,
even if cached requests still work. A corrected hbla.ke record with a misspelled
target returned HTTP 530/error 1016; correcting the suffix restored HTTP 200.
Validate public A/AAAA responses, then ordinary client requests and cellular
access. A `curl --resolve` success bypasses DNS and is not enough to declare
DNS repaired. Negative caches can outlive the fix.

Confirm the two exact hostname routes to `http://mushr:8080`, catch-all 404,
private routing disabled, DNS/edge policy, external and LAN requests in Caddy
logs, monitoring, fresh SSH and denied trusted-network connections. Reboot and
repeat checks before retiring replacement/old hardware. Record the new commit,
release manifest and tested backup/restore result. A Git pull does not install
system policy files; run the reviewed steps for each restored host.
