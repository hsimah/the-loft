# Off-site backups

**Shelved 2026-10-26: built and tested, not deployed.** `BACKUP_ENABLED="false"` in [host.conf](../../hosts/space-needle/host.conf), so setup.sh installs no timers, and the Homepage tile is off. No Google credential or repository exists yet. Backups will be planned for space-needle and helarctos as a whole before this returns; the design below (D10, D11) still stands. To turn it on, follow Setup, set `BACKUP_ENABLED="true"`, uncomment the tile, and run setup.sh.

Encrypted [restic](https://restic.readthedocs.io) snapshots of Mercurius (Paperless and the wiki) and Kennl's Forgejo go to Google Drive through rclone. restic encrypts on space-needle; Google sees opaque pack files and never holds a key. Script: [loft-backup.sh](../../control-plane/loft-backup.sh), installed by setup.sh as `loft-backup`. Settings (`BACKUP_*`) are in [host.conf](../../hosts/space-needle/host.conf). Plan for the remaining services: [automation plans](../../automation/plans/backups.md).

| Job | Repository | Backs up |
|---|---|---|
| `mercurius` | vault | Paperless's `document_exporter` output (`/mercurius/export`), a `pg_dump` and the Paperless image tag, staged in `/mercurius/backup/stage`; the SilverBullet folder (`/mercurius/silverbullet`, revisions included), copied live |
| `forgejo` | open | `forgejo dump`, a `pg_dump` and `app.ini`, staged in `/var/lib/loft/backup/stage` and removed after each run |

Nightly at `BACKUP_TIME`, a weekly prune and `restic check` reading a 5% data subset, from systemd timers (`systemctl list-timers 'loft-backup*'`). Retention: 7 daily, 4 weekly, 12 monthly; the vault also keeps every year.

## How the keys are kept

- **Two repositories, two passwords**: `<remote>/vault` and `<remote>/open`. Open-zone jobs cannot read vault backups.
- The vault password's working copy is `/mercurius/backup/restic.pass`, inside the encrypted volume: a stolen root disk cannot decrypt the vault backups, and the job skips while the vault is locked. The open password is `/etc/loft/restic/open.pass`.
- Each password also lives in the password manager and on the printed recovery sheet below. Nothing needed to restore depends on space-needle or the vault.
- The rclone config (`/etc/loft/rclone/gdrive.conf`, root, mode 600) holds a Drive token. Without the passwords it only reaches ciphertext.

## While the vault is locked

The `mercurius` job skips; Forgejo still runs. Skipping is silent, so each job has an Uptime Kuma monitor that goes down when its heartbeat lapses, and the weekly check also fails and notifies if a job has no success in 3 days.

## Alerts

- **Homepage Backups tile**: counts up and down for a Kuma status page that lists the monitors. A failed job pushes `down`; a skipped or missed one lapses to `down`.
- **ntfy**: `BACKUP_NTFY_URL` in host.conf, once ntfy is deployed (empty until then).
- `journalctl -u loft-backup` and `-u loft-backup-check`.

## Setup (once)

Run from `/srv/the-loft` on space-needle, one at a time.

1. **Google credential.** In Google Cloud Console create a project, enable the Drive API, and create an OAuth client (Desktop app). Set the OAuth consent screen's publishing status to **In production**: in Testing, Google expires the refresh token after 7 days. `drive.file` is not a sensitive scope, so no verification is needed. Note the client ID and secret for the recovery sheet.
2. **rclone remote.** `drive.file` limits rclone to files this client created, so a restore must use the same client ID and secret.

   ```bash
   sudo install -d -m 700 /etc/loft/rclone
   sudo rclone config --config /etc/loft/rclone/gdrive.conf
   ```

   New remote `gdrive`, type `drive`, your client ID and secret, scope `drive.file`, no service account; on a headless host answer `n` to auto config and run the printed `rclone authorize` command on a machine with a browser. Then `sudo chmod 600 /etc/loft/rclone/gdrive.conf`.
3. **Passwords.** Generate two, put each in the password manager and on the recovery sheet:

   ```bash
   openssl rand -base64 33
   ```

   Open: `sudo install -d -m 700 /etc/loft/restic`, then write the password to `/etc/loft/restic/open.pass` (mode 600). Vault, with the vault unlocked: `sudo install -d -m 700 /mercurius/backup`, then write it to `/mercurius/backup/restic.pass` (mode 600).
4. **Install.** `sudo bash setup.sh` installs restic (0.16 or newer), rclone, the script and the timers.
5. **Create the repositories** (vault unlocked): `sudo loft-backup init`.
6. **Monitors.** In Uptime Kuma add a Push monitor for each of `mercurius`, `forgejo` (heartbeat interval 26 h, retries 0) and `check` (8 days), and a status page listing them. Put the status page's slug in Houstn's `.env` as `HOMEPAGE_VAR_BACKUP_KUMA_SLUG`, then `sudo loft-ctl start houstn`. Write each push URL, without the query string, to `/etc/loft/backup-push` (root, mode 600), one `<job> <url>` per line.
7. **First run**: `sudo systemctl start loft-backup`, then `journalctl -u loft-backup -n 40` and `sudo systemctl start loft-backup-check`.

`loft-backup` has no listing command; list snapshots with restic directly:

```bash
sudo RCLONE_CONFIG=/etc/loft/rclone/gdrive.conf RESTIC_PASSWORD_FILE=/etc/loft/restic/open.pass \
  restic -r rclone:gdrive:the-loft/open snapshots
```

## Restore

Practice this on a scratch machine with only the recovery sheet. You need restic 0.16 or newer, rclone, and Docker for Paperless.

### 1. Reach the repositories

Create the rclone remote with the sheet's client ID and secret (scope `drive.file`) and sign in as the sheet's Google account:

```bash
rclone config        # new remote "gdrive", type drive, client ID and secret from the sheet, scope drive.file
export RESTIC_REPOSITORY=rclone:gdrive:the-loft/open
read -rs RESTIC_PASSWORD && export RESTIC_PASSWORD     # the OPEN password from the sheet
restic snapshots
```

For the vault use `.../vault` and the vault password.

### 2. Mercurius

```bash
export RESTIC_REPOSITORY=rclone:gdrive:the-loft/vault   # and the VAULT password
restic restore latest --tag mercurius --target ~/restore
ls ~/restore/mercurius/silverbullet/spaces/home
git -C ~/restore/mercurius/silverbullet/spaces/home log -3
cat ~/restore/mercurius/backup/stage/paperless-image.txt   # the Paperless image that exported
```

Wiki pages and their git history present means the wiki half is good. To bring it back, copy the folder to `/mercurius/silverbullet` on an unlocked vault, owned by littledog (UID 1003).

Import into a scratch Paperless of that same image tag; `<image>` is the file's content:

```bash
docker network create scratch
docker run -d --name db --network scratch -e POSTGRES_DB=paperless -e POSTGRES_USER=paperless -e POSTGRES_PASSWORD=scratch postgres:18
docker run -d --name redis --network scratch valkey/valkey:9-alpine
docker run -d --name paperless --network scratch -p 8000:8000 \
  -e PAPERLESS_DBENGINE=postgresql -e PAPERLESS_DBHOST=db -e PAPERLESS_DBNAME=paperless \
  -e PAPERLESS_DBUSER=paperless -e PAPERLESS_DBPASS=scratch -e PAPERLESS_REDIS=redis://redis:6379 \
  -e PAPERLESS_SECRET_KEY=scratch -v ~/restore/mercurius/export:/usr/src/paperless/export \
  <image>
docker exec paperless document_importer /usr/src/paperless/export
```

Open `http://localhost:8000`, sign in with an existing account, and confirm a known document opens with its OCR text. `~/restore/mercurius/backup/stage/paperless.dump` is a `pg_restore -Fc` dump of the same database, for restoring in place without a re-import.

On space-needle, restore into an unlocked, newly created vault ([Mercurius](../services/mercurius.md#create-the-volume-once)) and import there.

## Recovery sheet

Print this, fill it in, keep it in the safe with the LUKS recovery passphrase and header USB stick. Both of you must be able to find it.

```
THE LOFT — BACKUP RECOVERY SHEET                       Filed: ____________

Google account:      ______________________________  (sign-in recovery: ____________)
rclone client ID:    ______________________________________________
rclone client secret:______________________________________________
Drive folder:        the-loft   (repositories: the-loft/vault, the-loft/open)

OPEN  repository password (Forgejo):
  ______________________________________________
VAULT repository password (Mercurius):
  ______________________________________________

Steps: install restic (0.16+) and rclone. rclone config: remote "gdrive", type
drive, the client ID and secret above, scope drive.file, sign in as the Google
account. Then follow "Restore" in docs/operations/backups.md (printed copy
attached): restic restore latest --tag mercurius|forgejo --target ~/restore.
Paperless: import with document_importer into a Paperless of the image tag
in mercurius/backup/stage/paperless-image.txt.
```

## Troubleshooting

- **`loft-backup: another run is in progress`**: the weekly prune holds the lock; the next night resumes.
- **`mercurius: vault is locked; skipping`**: unlock it ([Mercurius](../services/mercurius.md#after-every-reboot)); the next nightly run backs up.
- **`forget` rejects `unlimited`**: restic older than 0.16.
- **Drive returns `invalid_grant`** after a week: the consent screen is still in Testing. Publish it, and re-run step 2.
- **A restore sees an empty Drive folder**: the rclone client differs from the one that wrote the files; `drive.file` shows only that client's files.
