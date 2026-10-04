# Hubbl — photo library

[Compose](../../services/hubbl/docker-compose.yml) runs Immich on space-needle: server (`hubbl`), machine learning (`hubbl-ml`), Valkey (`hubbl-redis`) and Immich's own Postgres (`hubbl-db`). Photos arrive via the [OneDrive migration](../operations/onedrive-migration.md).

| Host path | Contents |
|---|---|
| `/mammoth/hubbl/library` | Originals, thumbnails and transcodes Immich owns |
| `/opt/hubbl/db` | Postgres — asset, album and face metadata |
| `/mammoth/hubbl/staging` | **Temporary** OneDrive drain target; delete after import |

The library and the database are one unit. Immich addresses files under `/data` by content hash and resolves them through Postgres, so restoring one without the other gives a catalogue pointing at absent files. Dump with `pg_dumpall`; never copy `/opt/hubbl/db` from under a running cluster, and never reorganise the library from the host side.

`hubbl.hsimah.com` is **on the tunnel's public hostname list** so the mobile app can back up away from home. The name is first-level on purpose: Cloudflare's free Universal SSL covers `hsimah.com` and `*.hsimah.com` but not a second level like `*.loft.hsimah.com`, which would need paid Advanced Certificate Manager. `hubbl.loft.hsimah.com` stays LAN-only.

Immich has **no two-factor authentication** for local accounts and **no public registration** — the register page exists only until the first admin is created, and after that users are added from Administration → Users. So the admin password is the single factor, with no account-creation surface behind it. Cloudflare Access would add a gate but breaks the mobile app, which cannot complete its browser login. OIDC against an external provider is the only supported way to add a second factor.

dnsmasq answers `hubbl.hsimah.com` with `192.168.86.28`, so uploads from the LAN go straight to Caddy and skip the tunnel's size cap. The route in [the Caddyfile](../../services/mushr/Caddyfile) does not prove the hostname is published; check Cloudflare.

## Setup

1. Copy [.env.example](../../services/hubbl/.env.example). Generate `DB_PASSWORD` with `openssl rand -hex 32` **before** the first start — Postgres reads it only when initialising an empty `/opt/hubbl/db`, and changing it later locks the server out of its own database.
2. `sudo bash setup.sh` to provision the directories, then `sudo loft-ctl start hubbl` and `loft-ctl health hubbl`.
3. Register the first account **before** publishing — Immich makes the first account the admin, and there is no way to close registration while the server has none. Do it over the LAN.
4. Publish `hubbl.hsimah.com` on the tunnel in Cloudflare, pointing at Caddy over HTTPS. Confirm a test upload from the phone app on mobile data before trusting it with a backup; a LAN test resolves through dnsmasq and proves nothing about the tunnel.

## Upload size over the tunnel

The Caddy route sets no request-body limit deliberately: a cap surfaces in the mobile app as a silent backup failure. The real ceiling is Cloudflare's per-request limit — **100 MB on the free plan** — which this repository does not control.

The symptom is specific: phone photos sync anywhere, long videos fail only off-LAN and succeed at home. Check the file size against the plan limit before suspecting Immich. LAN uploads do not traverse the tunnel — but only because dnsmasq answers the public name locally. Remove that entry and every upload is capped, everywhere.

## Hardware acceleration

`hubbl` has `/dev/dri` for Quicksync transcoding — the **same iGPU Plex uses**. Device access is shared safely; throughput is not. Run bulk imports when nobody is watching.

ML runs on CPU. The OpenVINO variant (`-openvino` tag suffix plus `device_cgroup_rules` and `/dev/dri` from upstream's `hwaccel.ml.yml`) moves smart search and face detection onto that same iGPU, making it a third consumer. Enable deliberately, not alongside another change. Unbenchmarked on this host.

## Upgrades

Immich moves its schema on minor releases and **does not support downgrades**; reverting the tag does not revert a migration. Read [upgrades](../operations/upgrades.md) and dump the database first.

The `hubbl-redis` and `hubbl-db` digests are upstream's own, part of the release contract rather than independent choices — Immich's Postgres carries vector extensions version-matched to the server, so stock `postgres` breaks it. Move all four tags together from the target release's compose file.

## Troubleshooting

- **Database authentication fails at start:** `DB_PASSWORD` changed after the cluster was initialised. Fix with `ALTER ROLE` inside `hubbl-db`; re-initialising loses the catalogue.
- **Files on disk, absent in the UI:** library and database have diverged. Do not reorganise the library by hand.
- **Large videos fail only away from home:** the tunnel limit above.
- **Slow first pass:** face detection and smart search run over every asset on CPU. Check `hubbl-ml` logs for progress.
- **Apparent duplicates:** Immich deduplicates by checksum, so re-running an import is safe. Genuine source duplicates resolve in Immich's duplicate view, not in staging.

Deployed on space-needle 2026-10-03: containers healthy, both Caddy routes serving, the tunnel hostname live and the library importing. Pins come from the upstream v3.2.4 release compose.
