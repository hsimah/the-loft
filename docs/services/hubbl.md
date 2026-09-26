# Hubbl — photo library

[Compose](../../services/hubbl/docker-compose.yml) runs Immich on space-needle: the server (`hubbl`), machine learning (`hubbl-ml`), Valkey (`hubbl-redis`) and Immich's own Postgres build (`hubbl-db`). No other fleet host runs it. Photos arrive from OneDrive via the [migration runbook](../operations/onedrive-migration.md).

## State and boundaries

| Host path | Contents |
|---|---|
| `/mammoth/hubbl/library` | Every original, thumbnail and transcode Immich owns |
| `/opt/hubbl/db` | Postgres cluster — album, face, and asset metadata |
| `/mammoth/hubbl/staging` | **Temporary** OneDrive drain target; delete after import |

Immich addresses files under `/data` by content hash and records their location in Postgres. The library and the database are one unit: restoring one without the other produces a catalogue pointing at absent files, or orphaned files no album references. Back them up together, and dump Postgres with `pg_dumpall` rather than copying `/opt/hubbl/db` from under a running cluster.

Unlike the rest of the loft names, `hubbl.loft.hsimah.com` is **on the Cloudflare Tunnel's public hostname list**, so the mobile app can back up away from home. Immich's own login is therefore the only thing between the internet and the entire photo library — not a LAN boundary, not basic auth. Keep signup disabled after the first account, use a strong password, and enable two-factor in Immich itself. As always, the repository route does not prove the hostname is actually published; verify in the Cloudflare dashboard.

## First setup

1. Copy [.env.example](../../services/hubbl/.env.example). Generate `DB_PASSWORD` with `openssl rand -hex 32` **before** the first start — Postgres reads it only when initialising an empty `/opt/hubbl/db`, and changing it later locks the server out of its own database.
2. Provision the declared directories (`sudo bash setup.sh`) and start the service:

   ```bash
   sudo loft-ctl start hubbl
   loft-ctl health hubbl
   ```

3. Create the first account at `https://hubbl.loft.hsimah.com`. Immich makes the first registered user the admin, so do this immediately — the hostname is publicly reachable. Then disable signup in Administration → Settings.
4. Publish the hostname on the tunnel in the Cloudflare dashboard, and confirm the mobile app can log in and upload one test photo before trusting it with a backup.
5. For the OneDrive import, follow the [migration runbook](../operations/onedrive-migration.md).

## Upload size over the tunnel

Caddy sets no request-body limit on this route, deliberately: a cap would surface in the mobile app as a silent backup failure rather than an error. The real ceiling on tunnelled uploads is Cloudflare's per-request body limit, which is **100 MB on the free plan** and not something this repository controls.

The consequence is specific and easy to misdiagnose: phone photos and short clips sync fine from anywhere, while long videos fail only when the phone is off the LAN and succeed the moment it comes home. If that pattern appears, check the video's size against the plan limit before looking at Immich. Uploads over `http://hubbl.space-needle` and `https://hubbl.loft.hsimah.com` from the LAN do not traverse the tunnel and are not subject to it.

## Hardware acceleration

`hubbl` has `/dev/dri` for Quicksync video transcoding. This is the **same iGPU Plex uses** — device access is shared safely, but throughput is not. A bulk video-transcode job triggered right after a large import competes directly with Plex playback on the same silicon. Run large imports when nobody is watching, or accept the transcoding fallback.

Machine learning runs on CPU. The OpenVINO variant (image tag suffix `-openvino`, plus `device_cgroup_rules` and `/dev/dri` from upstream's `hwaccel.ml.yml`) moves smart search and face detection onto that same iGPU. It is a real speedup for the initial catalogue pass and a third consumer of one GPU; enable it deliberately, not as part of another change. These are configuration notes, not measurements — nothing here has been benchmarked on this host.

## Upgrades

Immich moves its schema on minor releases and **does not support downgrades**. Reverting the tag in Git does not revert a migration that has already run. Read [upgrades and backups](../operations/upgrades.md), dump the database, and treat a version bump as its own change.

The `hubbl-redis` and `hubbl-db` pins are upstream's own digests from the v3.2.2 release compose, not independent choices. Immich's Postgres image carries required vector extensions version-matched to the server; substituting stock `postgres` breaks it. Move all four tags together, from the release compose of the target version.

## Troubleshooting

- **Server will not start, database authentication fails:** `DB_PASSWORD` was changed after the cluster was initialised. Fix it with `ALTER ROLE` inside `hubbl-db`, or match `.env` back to the original value. Re-initialising means losing the catalogue.
- **Photos present on disk, absent in the UI:** the library and database have diverged. Do not reorganise `/mammoth/hubbl/library` by hand — Immich resolves files through Postgres, not the directory layout.
- **Large videos fail only away from home:** see the tunnel upload limit above.
- **Slow first catalogue pass:** expected. Face detection and smart search run over every asset on CPU; check `hubbl-ml` logs for progress rather than assuming a hang.
- **Import shows duplicates:** Immich deduplicates by checksum, so re-running the CLI upload is safe. Genuine duplicates in the OneDrive source remain duplicates — resolve them in Immich's duplicate view after the import, not in staging.

## Status

Proposed configuration, not a verified deployment. Nothing in this page has been applied to space-needle or validated against a running Immich instance; the version pins come from the upstream v3.2.2 release compose. The Caddy routes here could not be checked with `caddy validate` when written — no Docker daemon was available — so CI is the first real validation.
