# Open work

Items needing live evidence or a decision. None of these are done unless stated.

| Area | Work |
|---|---|
| Backups | No off-host backup/restore exists for any host. Clog SQLite, Pawst content/state, Viking `/etc/loft` secrets and service `.env` files need encrypted off-host copies and a tested restore |
| Viking | Enable the memory cgroup (`cgroup_disable=memory` is on the boot line, so Compose memory limits are not enforced), then reboot and recheck. Remove the stale `address=/viking/192.168.86.26` dnsmasq entry. Enroll a second admin. Verify Cloudflare edge HTTPS redirect and IPv6 denial probes |
| Clog | First live run of `loft-ctl deploy clog`; scheduled backups; capacity measurement on the Pi; account reset/recovery in the app |
| Fjord | Validate Pawst dev/test live. Confirm its network manager; the watchdog defaults to dhcpcd |
| Woodstock | Test Wi-Fi firmware recovery |
| Audiobookshelf | Verify Android, a second phone and cross-device progress sync |
| Stellarr | Hardlink-safe imports need a shared-parent mount migration |
| Sputnik | Test the empty-inbox path in deployed n8n; add an explicit empty-mail branch if it stalls |
| Identities | Record actual littledog UID/GID and Plex runtime identity; the Plex example uses 1004 while fresh setup uses 1003 |
| Beszel | Confirm hub-side resolution and per-system tokens |
| Exposure | Check live Cloudflare hostnames, Plex Remote Access/router state and granted Google scopes |
| Images | Find maintained Snapclient/VPN images (not the old `v3.12.3` VPN tag); pin Caddy's Cloudflare module source; check Jackett self-update |
| loft-ctl | Pull/build before `down` in rebuild; stop suppressing registry pull errors |
| OneDrive puller | **Kept, not torn down.** `control-plane/onedrive-pull.sh`, the `ONEDRIVE_PULL_*` block in space-needle's host.conf and `tests/test-onedrive-pull.sh` stay in place: the rest of the OneDrive account still has to be fetched for the document store below. Disabled, not deleted (`b9066ae`). To reuse, retarget `ONEDRIVE_PULL_REMOTE`/`ONEDRIVE_PULL_DEST` and set `ONEDRIVE_PULL_ENABLED="true"`. `/etc/loft/rclone/rclone.conf` is deliberately still on the host for the same reason; cancel OneDrive only after both fetches are done. See the [migration runbook](../docs/operations/onedrive-migration.md) |
| Documents (proposed) | A document store alongside Hubbl, fed from the remainder of OneDrive. Needs a name (dog/space wordplay), a product decision (Paperless-ngx for OCR'd documents, or a general file service) and a `/mammoth/<name>` layout. `/mammoth/hubbl/staging` can be reclaimed once the photo source is confirmed unneeded; the document fetch should use its own staging directory |
| Oxbow (proposed) | Brisbane Pi+NAS at Kangaroo Point, named for the river's oxbow bend. Syncthing-only replica of `/mammoth/photos` and `/mammoth/documents`. Not built |
