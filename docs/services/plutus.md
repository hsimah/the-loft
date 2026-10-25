# Plutus — household vault

[Compose](../../services/plutus/docker-compose.yml) runs [Paperless-ngx](https://docs.paperless-ngx.com) (`plutus`) on space-needle for financial, medical and personal records, with Postgres (`plutus-db`), Valkey (`plutus-redis`), Gotenberg and Tika (`plutus-gotenberg`, `plutus-tika`) for email and office files. Named for the god of wealth and buried ore and gems. Standard OCR only; AI comes later ([plan](../../automation/plans/plutus.md)). Deployed on space-needle 2026-10-25; egress probe confirmed no route out.

| Path | Contents |
|---|---|
| `/dev/ubuntu-vg/plutus` | 250 GB LVM volume on the NVMe, LUKS2 |
| `/plutus` | The unlocked volume (XFS): `data`, `media` (originals and archived PDFs), `consume`, `export`, `db`, `redis` |

Everything Plutus stores, including Postgres with the OCR text, is on the encrypted volume. Its directories are created only by [plutus-vault.sh](../../control-plane/plutus-vault.sh) after it has confirmed `/plutus` is the vault, never by setup.

## Isolation

- **Locked means down.** Every bind uses `create_host_path: false`. With the vault locked, `/plutus` is an empty directory on the root disk and Docker refuses to start Plutus. It cannot initialise an empty archive there. `setup.sh` skips Plutus until the mount exists (`SERVICE_REQUIRES_MOUNT` in [host.conf](../../hosts/space-needle/host.conf)).
- **No route out.** Plutus's own network and `plutus-proxy` are both Docker `internal` networks. `plutus-proxy` is shared only with Caddy, through space-needle's [Mushr override](../../hosts/space-needle/overrides/mushr/docker-compose.override.yml). Plutus is not on `loft-proxy`.
- `https://plutus.loft.hsimah.com`, LAN only; never on the tunnel. One shared archive with an account each; enable two-factor authentication on both (Profile → Two-factor authentication).

## After every reboot

The vault stays locked until unlocked by hand; `loft-ctl health` reports Plutus down until then.

```bash
sudo control-plane/plutus-vault.sh unlock
loft-ctl start plutus
```

`plutus-vault.sh status` reports the state. To lock: `loft-ctl stop plutus`, then `sudo control-plane/plutus-vault.sh lock`.

## Create the volume (once)

Run from `/srv/the-loft`, one at a time:

1. `sudo lvcreate -L 250G -n plutus ubuntu-vg`
2. `sudo cryptsetup luksFormat --type luks2 /dev/ubuntu-vg/plutus`. Use a long passphrase and store it in the password manager.
3. `sudo cryptsetup luksAddKey /dev/ubuntu-vg/plutus`: a second, recovery passphrase (`openssl rand -base64 30`) for the printed recovery sheet in the safe ([backups plan](../../automation/plans/backups.md#how-private-is-too-private-d11)).
4. `sudo cryptsetup luksHeaderBackup /dev/ubuntu-vg/plutus --header-backup-file /root/plutus-luks-header.img`. A damaged header makes the volume unrecoverable even with the passphrase. Copy it to the USB stick in the safe, then `sudo shred -u` it on the host: with either passphrase it opens the vault.
5. `sudo cryptsetup open /dev/ubuntu-vg/plutus plutus`, then `sudo mkfs.xfs -L plutus /dev/mapper/plutus`.
6. `sudo control-plane/plutus-vault.sh unlock` mounts it and creates the directories.

Grow it later while it is online: `lvextend`, `cryptsetup resize plutus`, then `xfs_growfs /plutus`.

## Setup

1. Copy [.env.example](../../services/plutus/.env.example) and generate `DB_PASSWORD` and `PAPERLESS_SECRET_KEY` with `openssl rand -hex 32` **before** the first start.
2. `sudo bash setup.sh` creates the `plutus-proxy` network. Then `loft-ctl start mushr` recreates Caddy on it.
3. With the vault unlocked: `loft-ctl start plutus`, then `loft-ctl health plutus`.
4. Open `https://plutus.loft.hsimah.com` and create the first account, which becomes the superuser. Create the second account under Settings → Users & Groups as a superuser too: owners otherwise hide documents from each other, and either superuser can reset the other's password or two-factor. Turn on two-factor for both.
5. Confirm there is no way out: `sudo docker exec plutus curl -sS -m 5 https://1.1.1.1` must fail to connect (exit 7), not just fail DNS.

## Backups

**None yet.** The vault is one copy on one disk. Keep paper originals until the encrypted off-site backup exists ([plan](../../automation/plans/backups.md)). That backup will be `document_exporter` output plus a Postgres dump, not a copy of `/plutus` taken while it is running.

## Upgrades

Paperless and Postgres migrate one way. Run `document_exporter` and `pg_dump` first and read [upgrades](../operations/upgrades.md). The Postgres major (18) moves only with a dump and restore.

## Troubleshooting

- **`bind source path does not exist: /plutus/...`**: the vault is locked. Unlock it, then start Plutus.
- **`plutus-vault.sh` says another device is mounted**: something else is on `/plutus`; unmount it. The script never creates directories there.
- **502 from Caddy**: Plutus is stopped, or Mushr was not recreated after `plutus-proxy` was created (`sudo docker inspect mushr` should list both networks).
- **`plutus-db` logs `cannot create directory '/var/lib/postgresql'`**: `/plutus/db` is not traversable; it must be `755` (Postgres 18 only chowns its `18/docker` subdirectory).
- **Two-factor activation returns `{"success":false}`**: the code didn't match the secret. Paperless makes a new secret each time the dialog opens; delete the authenticator entry, open the dialog once, scan, and enter the code at once.
- **Database authentication fails at start**: `DB_PASSWORD` changed after the cluster was initialised. Fix it with `ALTER ROLE` inside `plutus-db`.
