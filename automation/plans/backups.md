# Off-site backups to Google Drive

**Yes, encrypt before upload, and use snapshots rather than an rsync mirror.** A mirror copies deletions, corruption and mistakes to the off-site copy on the next run. This is the first slice of the fleet backup work in [#108](https://github.com/hsimah/the-loft/issues/108) and the Backups row in [maintenance](../../plans/maintenance.md).

## Tool (D10)

| Option | What Google sees | Versions | Verdict |
|---|---|---|---|
| **restic** with an rclone Drive backend | Opaque pack files: total size, count, upload times | Snapshots, deduplicated, with retention | Recommended |
| rclone `crypt` remote | One encrypted file per file, names encrypted; per-file sizes visible | None (Drive's own 30-day trash only) | For a browsable copy, not a backup |
| Encrypted tarballs (`tar` + `age`) | One blob per run | Each run is a full copy | Works; restic does it better |

restic encrypts on the client (AES-256 with Poly1305); Google never holds the key. Check the Drive quota against the vault's expected size first.

Give rclone its own OAuth client with the `drive.file` scope, which limits it to files it created. That is a new Google credential, so it needs your approval: the existing ones are read-only Gmail and Calendar.

## How private is too private (D11)

The cipher is not the risk; losing the key is. Encryption becomes too private when:

- the only copy of the restic password sits inside the vault or on space-needle, so losing the host loses the backup;
- only one of you can restore it. The vault exists for household emergencies, including one where you are not available;
- the Google account itself is the single point of failure: a lockout means no backup.

So:

- **Two repositories, two passwords**: vault and open household. Open-zone automation can't read vault backups.
- **Key custody**: each password lives in the password manager ([#58](https://github.com/hsimah/the-loft/issues/58), [#117](https://github.com/hsimah/the-loft/issues/117)) and on a printed recovery sheet in the safe, with the restore steps. Bootstrap credentials must not depend on the vault they restore.
- **A second off-site copy** later: [Oxbow](../../plans/maintenance.md), the planned Brisbane Pi, as a Syncthing *untrusted* (encrypted) device for the vault.

## What each service backs up

| Service | Back up | Notes |
|---|---|---|
| Vault | `document_exporter` output + Postgres dump | The export is portable across Paperless versions |
| Wiki | The SilverBullet space | Forgejo also has its history |
| Calendar | Radicale's collection folder | Plain `.ics` |
| Recipes | Mealie's backup zip | |
| n8n | Data folder + `N8N_ENCRYPTION_KEY` | Without the key, credentials are lost |
| Forgejo | `forgejo dump` + `pg_dump` + `app.ini` | Open work in [Kennl](../../docs/services/kennl.md) |

Nightly, from a timer installed by setup.sh. Weekly `restic check` reading a data subset. Retention: 7 daily, 4 weekly, 12 monthly; vault yearlies kept forever. Failures go to ntfy.

**Done when** a vault and a wiki snapshot are restored from Drive onto a scratch machine, using only the recovery sheet.
