# OneDrive → Hubbl migration

One-off drain of a OneDrive account into [Hubbl](../services/hubbl.md). Temporary scaffolding — an rclone cron, a staging directory and a `cli` Compose profile — all removed in the last step. Delete this page with them.

**rsync cannot reach OneDrive**: no rsync daemon, no SSH endpoint, the transport is the Graph API. [onedrive-pull.sh](../../control-plane/onedrive-pull.sh) wraps `rclone copy` instead.

```
OneDrive ──rclone copy (cron, 10 min)──▶ /mammoth/hubbl/staging
                                                │
                                    immich-cli upload (once)
                                                ▼
                                    /mammoth/hubbl/library
```

`copy`, never `sync`: sync propagates remote deletions, so a mistyped remote path would delete the staging copy of photos already drained off the account.

## 1. Disk

Staging holds a second full copy until the import is verified, so `/mammoth` needs the library size twice plus headroom. Filling `/mammoth` stops Immich writes, Plex and the pull at once.

```bash
rclone --config /etc/loft/rclone/rclone.conf size onedrive:Pictures
df -h /mammoth
```

If both copies will not fit, import in batches (step 4) and delete each batch from staging as it lands.

## 2. Install the remote

Print the stanza from wherever the working rclone config already lives (`rclone config show onedrive`), then on space-needle:

```bash
sudo install -d -o root -g root -m 700 /etc/loft/rclone
sudo install -o root -g root -m 600 /dev/null /etc/loft/rclone/rclone.conf
sudo nano /etc/loft/rclone/rclone.conf      # paste the [onedrive] stanza
sudo rclone --config /etc/loft/rclone/rclone.conf lsd onedrive:
```

That file holds an **OAuth refresh token for the whole account**. Mode 600, root-owned, never committed; rclone rewrites it as tokens roll over, so it must stay writable.

`ONEDRIVE_PULL_REMOTE` in [host.conf](../../hosts/space-needle/host.conf) must match the remote name and path exactly — the puller cannot tell a typo from an empty folder, and both report "0 new files". Check `rclone version` too; distribution packages lag upstream and the OneDrive backend changes.

## 3. Seed and start

If the earlier manual clone is still on disk, copy it in first — rclone compares size and mtime, so seeded files are verified and skipped rather than re-downloaded. (`rsync` is correct *here*: this is a local copy.)

```bash
sudo rsync -a --info=progress2 /path/to/existing/clone/ /mammoth/hubbl/staging/
sudo chown -R littledog:pack-member /mammoth/hubbl/staging
cd /srv/the-loft && sudo bash setup.sh      # installs the cron
tail -f /var/log/loft/onedrive-pull.log
```

The first run takes hours. The cron keeps firing; each tick fails to take the `flock` and exits silently, so overlapping pulls are impossible. Throttling is expected — `--retries 1` makes a throttled run surrender the lock for the next tick rather than block behind rclone's backoff. Lower `ONEDRIVE_PULL_TPSLIMIT` or set `ONEDRIVE_PULL_BWLIMIT` if needed.

## 4. Import

Wait for `Up to date — 0 new files` across several consecutive ticks, and confirm the total matches step 1 — a single such line also appears when the remote path is wrong.

Create an API key (Account Settings → API Keys), set `IMMICH_API_KEY` in `services/hubbl/.env`, then run the import. The key needs, at minimum: `asset.upload`, `asset.read`, `album.create`, `album.read`, `albumAsset.create`, and the user-read permission the preflight uses. `albumAsset.create` is separate from `album.create` and is only reached after the assets have already uploaded, so a key missing it fails late, not early. Grant no delete permission; nothing in an import needs one. Select-all is defensible for a key revoked the same day.

```bash
cd /srv/the-loft
sudo docker compose -f services/hubbl/docker-compose.yml --profile cli run --rm cli \
  upload --recursive --album /import
```

`--album` creates one album per source folder, preserving the OneDrive structure; `--album-name` would flatten everything into one. Files loose at the top of staging land outside any album.

Staging mounts read-only, so a failed or repeated run cannot touch the source. Immich deduplicates by checksum, so re-running resumes. Point the last argument at a subdirectory to import in batches. Revoke the key afterwards.

The CLI pin must move with the server pin — it is versioned in lockstep. **`Error connecting to server` from this CLI almost never means the network.** It is the message for a missing API key, an insufficiently permissioned key, and a CLI too old for the server's API, all three. Before touching DNS or ports, check the key reaches the API:

```bash
sudo docker compose -f services/hubbl/docker-compose.yml --profile cli run --rm \
  --entrypoint sh cli -c 'wget -qO- --header="x-api-key: $IMMICH_API_KEY" \
  http://hubbl:2283/api/users/me | head -c 80'
```

JSON means the key and the network are both fine and the fault is the CLI itself.

## 5. Verify, then tear down

Check asset count against `find /mammoth/hubbl/staging -type f | wc -l`; spot-check dates and locations (files without EXIF fall back to mtimes the copy preserved); confirm videos, live photos and screenshots arrived, not just JPEGs; resolve duplicates in Immich.

Only then:

```bash
sed -i 's/^ONEDRIVE_PULL_ENABLED=.*/ONEDRIVE_PULL_ENABLED="false"/' hosts/space-needle/host.conf
sudo bash setup.sh                                    # removes the cron
sed -i 's/^IMMICH_API_KEY=.*/IMMICH_API_KEY=/' services/hubbl/.env
sudo shred -u /etc/loft/rclone/rclone.conf && sudo rmdir /etc/loft/rclone
sudo rm -rf /mammoth/hubbl/staging
```

`setup.sh` removes the cron unconditionally on every run, so the flag is what stops it; a hand-deleted cron file comes back. Then drop the `ONEDRIVE_PULL_*` block and the staging path from host.conf, the `cli` service from [Compose](../../services/hubbl/docker-compose.yml), and this page. Hubbl still needs a real backup covering the library and database together — see [upgrades](upgrades.md).

Not yet executed; the remote name, folder path and disk headroom are unverified.
