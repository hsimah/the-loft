# Open work

Items needing live evidence or a decision. None of these are done unless stated.

| Area | Work |
|---|---|
| Backups | No off-host backup/restore exists for any host. Clog SQLite, Pawst content/state, Viking `/etc/loft` secrets and service `.env` files need encrypted off-host copies and a tested restore |
| Viking | Enable the memory cgroup (`cgroup_disable=memory` is on the boot line, so Compose memory limits are not enforced), then reboot and recheck. Remove the stale `address=/viking/192.168.86.26` dnsmasq entry. Enroll a second admin. Verify Cloudflare edge HTTPS redirect and IPv6 denial probes |
| Clog | First live run of `loft-ctl deploy clog`; scheduled backups; capacity measurement on the Pi; account reset/recovery in the app |
| Fjord | Validate Pawst dev/test live. Confirm its network manager; the watchdog defaults to dhcpcd |
| Woodstock | Add the Upstairs stream ID to `I3_POWER_GROUPS`; test Wi-Fi firmware recovery |
| Audiobookshelf | Verify Android, a second phone and cross-device progress sync |
| Stellarr | Hardlink-safe imports need a shared-parent mount migration |
| Sputnik | Test the empty-inbox path in deployed n8n; add an explicit empty-mail branch if it stalls |
| Identities | Record actual littledog UID/GID and Plex runtime identity; the Plex example uses 1004 while fresh setup uses 1003 |
| Beszel | Confirm hub-side resolution and per-system tokens |
| Exposure | Check live Cloudflare hostnames, Plex Remote Access/router state and granted Google scopes |
| Images | Find maintained Snapclient/VPN images (not the old `v3.12.3` VPN tag); pin Caddy's Cloudflare module source; check Jackett self-update |
| loft-ctl | Pull/build before `down` in rebuild; stop suppressing registry pull errors |
| Oxbow (proposed) | Brisbane Pi+NAS at Kangaroo Point, named for the river's oxbow bend. Syncthing-only replica of `/mammoth/photos` and `/mammoth/documents`. Not built |
