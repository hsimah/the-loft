# Restore the Viking production role

For rebuilding Viking on the same or replacement Debian hardware with hostname `viking`. Not yet drilled end-to-end.

## Keep off-device (encrypted)

- Repo commit plus approved release archives/checksums (GitHub is not a backup).
- `/etc/loft` secrets, installed firewall/SSH/apt files, admin public key.
- `services/snoot/.env`, `services/mushr/.env`, `services/clog/.env`, Glances config.
- `/opt/pawst/prod`, `/var/lib/loft/deploy`, Clog SQLite backups.
- Cloudflare tunnel ID/routes/DNS targets and Tailscale grants. Wi-Fi credentials separately.

## 1. Host access and boundary

1. Minimal OS, NetworkManager, key-only `adminhabl`. Join only the isolated network.
2. Re-enroll in Tailscale (never reuse cloned node keys); restore grants for Blanco SSH and space-needle monitoring. Update Beszel/Homepage/firewall addresses if they change.
3. Clone `/srv/the-loft` at the reviewed commit and install the [hardening baseline](../../hosts/viking/hardening/README.md), adapting interface/addresses first:

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

4. With console access or a timed rollback: reload SSH, `systemctl daemon-reload`, enable `loft-firewall.service`, enable apt timers and dry-run `unattended-upgrade`. Disable Avahi.
5. Verify fresh SSH, monitoring, public HTTPS and **failing** trusted-LAN probes, then create `/etc/loft/dmz-ready`. A restored copy of that file proves nothing.

## 2. Provision without public ingress

```bash
sudo env COMPOSE_PROFILES= bash /srv/the-loft/setup.sh
```

Check littledog is 1003 with no Docker membership. On an already running host, stop ingress first: `sudo docker stop mushr-tunnel pawst`.

## 3. Restore Pawst content

```bash
hosts/viking/restore --plan
sudo hosts/viking/restore --apply
```

`--apply` checks the host, attestation, firewall and IDs, then force-refetches the releases pinned in [releases.json](../../hosts/viking/releases.json), starts only Mushr and Pawst, and checks both sites plus unknown-host 404. It never starts the tunnel. Keep `releases.json` current with each production release. Never swap a pin for `latest` to get past a failed download.

## 4. Enable ingress

Install `/etc/loft/viking-tunnel-token` (root:65532, 0640) and `services/mushr/.env` with `COMPOSE_PROFILES=public`, then:

```bash
sudo docker compose -f services/mushr/docker-compose.yml \
  -f hosts/viking/overrides/mushr/docker-compose.override.yml --profile public up -d mushr-tunnel
```

Current tunnel target: `77cdbc17-f2cb-4977-88e1-1fc4337e909c.cfargotunnel.com` (verify in the dashboard). Each zone needs a proxied apex CNAME to it — the suffix is **cfargotunnel.com**; a typo gives Cloudflare error 1016. Deleting tunnel hostname routes can delete the DNS records too, so recheck actual records after any route cleanup; `curl --resolve` bypasses DNS and proves nothing about it.

Verify both sites from cellular and LAN, monitoring, SSH and denied LAN probes; reboot and repeat. For a replacement running in parallel, use a separate tunnel until cutover and never run two active connectors on one tunnel.

## 5. Clog

`hosts/viking/restore` covers Pawst only. Restore Clog from its database backup per the [Clog runbook](../services/clog.md#backups-and-recovery).
