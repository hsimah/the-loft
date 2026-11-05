# OneDrive retirement

OneDrive is being emptied and then cancelled (paid until May 2027): photos into [Hubbl](../services/hubbl.md), documents into [Mercurius](../services/mercurius.md). The scaffolding is temporary: an rclone puller, its credential, `/mammoth/hubbl/staging` and Hubbl's `cli` Compose profile. Delete this page with them.

## State

- **Photos:** imported into Hubbl 2026-10-04. `/mammoth/hubbl/staging` still holds a copy; reclaim it once the photo source is confirmed unneeded.
- **Puller:** disabled (`ONEDRIVE_PULL_ENABLED="false"` in [host.conf](../../hosts/space-needle/host.conf)). The credential stays on space-needle for the next fetch.
- **Rest of the account:** not yet fetched. Plan: [documents](../automation/documents.md#getting-documents-in).

## Puller

[onedrive-pull.sh](../../control-plane/onedrive-pull.sh) wraps `rclone copy` on a cron (rsync cannot reach OneDrive; the transport is the Graph API). `copy`, never `sync`: sync propagates remote deletions, so a mistyped remote path would delete staging.

To run a fetch:

1. Set `ONEDRIVE_PULL_REMOTE` and `ONEDRIVE_PULL_DEST` in host.conf. Give each fetch its own staging directory, so one import's leftovers cannot be mistaken for another's.
2. Check space: `sudo rclone --config /etc/loft/rclone/rclone.conf size <remote>` and `df -h` on the destination.
3. Set `ONEDRIVE_PULL_ENABLED="true"`, run `loft-ctl setup` (installs the cron) and `tail -f /var/log/loft/onedrive-pull.log`.
4. Wait for `Up to date — 0 new files` over several ticks **and** a total matching step 2. A wrong remote path also reports 0 new files.
5. Set the flag back to `"false"` and rerun setup. Setup removes the cron on every run, so the flag is what stops it; a hand-deleted cron file comes back.

- `copy` re-downloads anything missing locally: pruning staging while the cron runs does not stick.
- Overlapping ticks fail to take the `flock` and exit silently.
- Throttling is expected; `--retries 1` gives up the lock to the next tick. Lower `ONEDRIVE_PULL_TPSLIMIT` or set `ONEDRIVE_PULL_BWLIMIT` if needed.

## Credential

`/etc/loft/rclone/rclone.conf` (root, mode 600, never committed) holds an **OAuth refresh token for the whole account**. rclone rewrites it as tokens roll over, so it must stay writable. To reinstall, print the stanza from a working config (`rclone config show onedrive`), then:

```bash
sudo install -d -o root -g root -m 700 /etc/loft/rclone
sudo install -o root -g root -m 600 /dev/null /etc/loft/rclone/rclone.conf
sudo nano /etc/loft/rclone/rclone.conf      # paste the [onedrive] stanza
sudo rclone --config /etc/loft/rclone/rclone.conf lsd onedrive:
```

## Importing photos into Hubbl

Set `IMMICH_API_KEY` in `services/hubbl/.env` (Account Settings → API Keys). The key needs `asset.upload`, `asset.read`, `album.create`, `album.read`, `albumAsset.create` and user read; no delete. `albumAsset.create` is only used after the uploads, so a key missing it fails late. Revoke it afterwards.

```bash
sudo docker compose -f services/hubbl/docker-compose.yml --profile cli run --rm cli \
  upload --recursive --album /import
```

`--album` makes one album per source folder. Staging mounts read-only, and Immich deduplicates by checksum, so reruns resume. The CLI pin moves with the server pin.

**`Error connecting to server` almost never means the network**: it also covers a missing key, a key without permissions and a CLI too old for the server. Check the key first:

```bash
sudo docker compose -f services/hubbl/docker-compose.yml --profile cli run --rm \
  --entrypoint sh cli -c 'wget -qO- --header="x-api-key: $IMMICH_API_KEY" \
  http://hubbl:2283/api/users/me | head -c 80'
```

## Teardown

Once every fetch is imported and checked:

```bash
sed -i 's/^ONEDRIVE_PULL_ENABLED=.*/ONEDRIVE_PULL_ENABLED="false"/' hosts/space-needle/host.conf
loft-ctl setup
sudo shred -u /etc/loft/rclone/rclone.conf && sudo rmdir /etc/loft/rclone
sudo rm -rf /mammoth/hubbl/staging <other staging directories>
```

Then remove the puller, its host.conf block and test, the `cli` profile and this page from the repository, and cancel OneDrive. This is a migration, not a backup: Hubbl still needs one ([upgrades](upgrades.md)).
