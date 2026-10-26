# Off-site backups to Google Drive

Encrypted restic snapshots to Google Drive through rclone (D10), not an rsync mirror: a mirror copies deletions, corruption and mistakes to the off-site copy on the next run. This is the first slice of the fleet backup work in [#108](https://github.com/hsimah/the-loft/issues/108) and the Backups row in [maintenance](../../plans/maintenance.md).

**Shelved 2026-10-26.** Built and tested for Plutus, Mercurius and Forgejo but not deployed: no Google credential or repository exists, and `BACKUP_ENABLED="false"`. Backups will be planned for space-needle and helarctos as a whole, including every service's configuration and `.env`, before this returns. Setup, restore and the recovery sheet are in the [runbook](../../docs/operations/backups.md). Check the Drive quota against the vault's expected size first.

## Key custody (D11)

The cipher is not the risk; losing the key is. Encryption becomes too private when:

- the only copy of the restic password sits inside the vault or on space-needle, so losing the host loses the backup;
- only one of you can restore it. The vault exists for household emergencies, including one where you are not available;
- the Google account itself is the single point of failure: a lockout means no backup.

So there are two repositories and two passwords, vault and open household; open-zone automation can't read vault backups. Each password lives in the password manager ([#58](https://github.com/hsimah/the-loft/issues/58), [#117](https://github.com/hsimah/the-loft/issues/117)) and on a printed recovery sheet in the safe, with the restore steps and the rclone client ID and secret. Bootstrap credentials must not depend on the vault they restore.

A second off-site copy later: [Oxbow](../../plans/maintenance.md), the planned Brisbane Pi, as a Syncthing *untrusted* (encrypted) device for the vault.

## Still to add

| Service | Back up | Notes |
|---|---|---|
| Calendar | Radicale's collection folder | Plain `.ics` |
| Recipes | Mealie's backup zip | |
| n8n | Data folder + `N8N_ENCRYPTION_KEY` | Without the key, credentials are lost |

Each would be a new job in `loft-backup` and a row in the runbook. Failures would show on a Homepage Backups tile (off while shelved), and in ntfy once that is deployed.

**Done when** a vault and a wiki snapshot are restored from Drive onto a scratch machine, using only the recovery sheet.
