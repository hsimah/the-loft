# Hubbl — photo library

[Compose](../../services/hubbl/docker-compose.yml) runs Immich on space-needle: server (`hubbl`), machine learning (`hubbl-ml`), Valkey (`hubbl-redis`) and Immich's own Postgres (`hubbl-db`). Photos arrive via the [OneDrive migration](../operations/onedrive-migration.md).

| Host path | Contents |
|---|---|
| `/mammoth/hubbl/library` | Originals, thumbnails and transcodes Immich owns |
| `/opt/hubbl/db` | Postgres — asset, album and face metadata |
| `/mammoth/hubbl/staging` | **Temporary** OneDrive drain target; delete after import |

The library and the database are one unit. Immich addresses files under `/data` by content hash and resolves them through Postgres, so restoring one without the other gives a catalogue pointing at absent files. Dump with `pg_dumpall`; never copy `/opt/hubbl/db` from under a running cluster, and never reorganise the library from the host side.

`hubbl.loft.hsimah.com` is **on the tunnel's public hostname list** so the mobile app can back up away from home — Immich's own login is the only boundary in front of the whole library. Keep signup disabled after the first account and enable two-factor. The route in [the Caddyfile](../../services/mushr/Caddyfile) does not prove the hostname is published; check Cloudflare.

## Setup

1. Copy [.env.example](../../services/hubbl/.env.example). Generate `DB_PASSWORD` with `openssl rand -hex 32` **before** the first start — Postgres reads it only when initialising an empty `/opt/hubbl/db`, and changing it later locks the server out of its own database.
2. `sudo bash setup.sh` to provision the directories, then `sudo loft-ctl start hubbl` and `loft-ctl health hubbl`.
3. Register the first account immediately at `https://hubbl.loft.hsimah.com` — Immich makes it the admin and the hostname is publicly reachable. Disable signup in Administration → Settings.
4. Publish the hostname on the tunnel in Cloudflare, then confirm a test upload from the phone app before trusting it with a backup.

## Upload size over the tunnel

The Caddy route sets no request-body limit deliberately: a cap surfaces in the mobile app as a silent backup failure. The real ceiling is Cloudflare's per-request limit — **100 MB on the free plan** — which this repository does not control.

The symptom is specific: phone photos sync anywhere, long videos fail only off-LAN and succeed at home. Check the file size against the plan limit before suspecting Immich. LAN uploads do not traverse the tunnel.

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

Not yet deployed; pins come from the upstream v3.2.4 release compose.
