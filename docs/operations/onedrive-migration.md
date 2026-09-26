# OneDrive → Hubbl migration

One-off procedure for draining a OneDrive account into [Hubbl](../services/hubbl.md) and switching it off. Everything here is temporary scaffolding with an explicit end: an rclone cron on space-needle, a staging directory on `/mammoth`, and a `cli` Compose profile. All three are removed in the last step.

**rsync cannot reach OneDrive.** There is no rsync daemon or SSH endpoint on the Microsoft side; the transport is the Graph API. [rclone](https://rclone.org/onedrive/) speaks it natively, so the puller is [onedrive-pull.sh](../../control-plane/onedrive-pull.sh) wrapping `rclone copy`.

## Shape of it

```
OneDrive ──rclone copy (cron, every 10 min)──▶ /mammoth/hubbl/staging
                                                      │
                                          immich-cli upload (once, at the end)
                                                      ▼
                                              /mammoth/hubbl/library
```

The pull is incremental and additive. It is `copy`, never `sync`: `sync` propagates remote deletions to the local side, so a mistyped remote path or a half-emptied OneDrive folder would delete photos already drained off the account. The cron can therefore run as long as you like without risk to the staging copy.

## 1. Plan the disk

Staging holds a second full copy of the photos until the import is verified, so `/mammoth` needs the library size **twice over** plus headroom. Check the OneDrive side and the free space before starting:

```bash
rclone --config /etc/loft/rclone/rclone.conf size onedrive:Pictures
df -h /mammoth
```

Running `/mammoth` out of space mid-import is the worst failure mode available here — it stops Plex recording, Immich writes and the pull at once. If the two copies will not fit, import in batches (step 5) and delete each batch from staging as it lands.

## 2. Install the rclone remote

The remote already exists from the earlier manual clone; this step moves it somewhere root's cron can read. On the machine that holds the working config, print the stanza:

```bash
rclone config show onedrive          # or whatever the remote is named
```

On space-needle, write it to a root-owned file:

```bash
sudo install -d -o root -g root -m 700 /etc/loft/rclone
sudo install -o root -g root -m 600 /dev/null /etc/loft/rclone/rclone.conf
sudo nano /etc/loft/rclone/rclone.conf     # paste the [onedrive] stanza
sudo rclone --config /etc/loft/rclone/rclone.conf lsd onedrive:
```

That file holds an **OAuth refresh token for the whole OneDrive account** — long-lived, and enough to read everything in it. Mode 600, root-owned, never in this repository. rclone rewrites the file in place as tokens roll over, so it must stay writable.

Two things to confirm before a long run. First, the remote name and path in `ONEDRIVE_PULL_REMOTE` must match this config exactly; the puller has no way to tell a typo'd path from an empty folder, and both look like "0 new files". Second, check `rclone version` — distribution packages lag upstream and the OneDrive backend does change. If the packaged version is much older than the one that produced the working config, install the upstream build before starting.

## 3. Seed from the existing clone (optional)

If the earlier manual clone is still on disk somewhere reachable, copy it into staging first. rclone compares size and modification time, so a seeded file is checked and skipped rather than re-downloaded — this can turn a multi-day first pull into an hour of verification.

```bash
sudo rsync -a --info=progress2 /path/to/existing/clone/ /mammoth/hubbl/staging/
sudo chown -R littledog:pack-member /mammoth/hubbl/staging
```

(`rsync` is the right tool *here* — this is a local copy, not OneDrive.)

## 4. Start the pull

`ONEDRIVE_PULL_ENABLED`, the remote, the destination and the interval are all in [space-needle's host.conf](../../hosts/space-needle/host.conf). `setup.sh` installs the script to `/usr/local/bin/loft-onedrive-pull`, its configuration to `/etc/default/loft-onedrive-pull`, and the cron entry:

```bash
cd /srv/the-loft
sudo bash setup.sh
sudo run-parts --report --test /etc/cron.d   # or just: cat /etc/cron.d/loft-onedrive-pull
```

Watch it:

```bash
tail -f /var/log/loft/onedrive-pull.log
```

The first run downloads the whole library and takes hours. The cron keeps firing every 10 minutes throughout; each tick fails to take the `flock` and exits silently, so the ticks queue up behind nothing. Overlapping pulls are not possible.

Throttling is expected on a large library — Graph API rate limits are per-account. The puller uses `--retries 1` on purpose, so a throttled run surrenders the lock and lets the next tick resume rather than sitting in rclone's own backoff. Lower `ONEDRIVE_PULL_TPSLIMIT` or set `ONEDRIVE_PULL_BWLIMIT` in host.conf if it becomes a problem.

## 5. Import into Immich

Wait for the signal. A finished drain looks like this in the log, repeated across several consecutive ticks:

```
Up to date — 0 new files, 48213 total in staging
```

One such line is not enough — it also appears when the remote path is wrong. Confirm the total matches `rclone size` from step 1 before treating the pull as complete.

Create an API key in Immich (Account Settings → API Keys), put it in `IMMICH_API_KEY` in `services/hubbl/.env`, then run the importer:

```bash
cd /srv/the-loft
sudo docker compose -f services/hubbl/docker-compose.yml --profile cli run --rm cli \
  upload --recursive --album-name "OneDrive" /import
```

Staging is mounted **read-only**, so a failed or repeated run cannot touch the source photos. Immich deduplicates by checksum, so re-running after an interruption resumes rather than duplicating. For a batched import, point the last argument at a subdirectory instead of `/import`.

That API key is a full-account credential — it can read and delete every photo in the library. Clear it from `.env` and revoke it in Immich once the import is done.

## 6. Verify before deleting anything

The whole point of the staging copy is that it survives a bad import. Do not skip this.

- Asset count in Immich against `find /mammoth/hubbl/staging -type f | wc -l`.
- Spot-check dates and locations. Files whose EXIF OneDrive stripped fall back to filesystem timestamps, which the rclone copy preserved but a careless `chown -R`/`touch` would not.
- Confirm live and motion photos, screenshots and videos all arrived — not just JPEGs.
- Check Immich's duplicate view. Genuine duplicates in the OneDrive source are still duplicates; resolve them here, not in staging.

## 7. Turn it off

In order, and only after step 6:

```bash
# 1. Stop the pulls
sed -i 's/^ONEDRIVE_PULL_ENABLED=.*/ONEDRIVE_PULL_ENABLED="false"/' \
  hosts/space-needle/host.conf
sudo bash setup.sh
test ! -f /etc/cron.d/loft-onedrive-pull && echo "cron removed"

# 2. Revoke the API key in Immich, then clear it from .env
sed -i 's/^IMMICH_API_KEY=.*/IMMICH_API_KEY=/' services/hubbl/.env

# 3. Remove the OneDrive credential
sudo shred -u /etc/loft/rclone/rclone.conf && sudo rmdir /etc/loft/rclone

# 4. Reclaim the staging space — last, and only after step 6 passed
sudo rm -rf /mammoth/hubbl/staging
```

`setup.sh` removes the cron and `/etc/default/loft-onedrive-pull` unconditionally on every run, so flipping the flag and re-running is the supported way to stop; deleting the cron file by hand works until the next `setup.sh` puts it back.

Then tidy the repository: drop the `ONEDRIVE_PULL_*` block and the `/mammoth/hubbl/staging` entry from `hosts/space-needle/host.conf`, the `cli` service from [the Compose file](../../services/hubbl/docker-compose.yml), and this page. Leaving dead migration scaffolding in place is how it gets mistaken for a live backup path later — it is not one, and Hubbl still needs a real backup covering `/mammoth/hubbl/library` and `/opt/hubbl/db` together. See [upgrades and backups](upgrades.md).

## Status

Proposed procedure. Not executed — no step here has been run against the real OneDrive account, the real rclone config or a live Immich instance, and the asset counts and log lines shown are illustrative. Verify the remote name, the OneDrive folder path and available disk before starting.
