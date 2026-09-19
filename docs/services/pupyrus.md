# Pupyrus — WordPress

[Compose](../../services/pupyrus/docker-compose.yml) runs WordPress/Apache (`pupyrus`), MariaDB and Redis on space-needle. WordPress joins `loft-proxy` and its private database network; DB/Redis remain on the private network. The `cli` profile provides one-shot WP-CLI. There is no WordPress host port: use `https://pupyrus.loft.hsimah.com` or `http://pupyrus.space-needle` through Caddy.

## Configuration and data

Copy [.env.example](../../services/pupyrus/.env.example). It defines database credentials, admin bootstrap credentials, table prefix/debug settings and the GraphQL JWT secret. Compose adds Redis settings and `FS_METHOD=direct`. Plugins still need installation/activation in WordPress; Redis Object Cache must be enabled in its settings.

| Host path | Data |
|---|---|
| `/opt/pupyrus/html` | WordPress code/config, plugins, themes and uploads |
| `/opt/pupyrus/db` | MariaDB data |

These are bind mounts. `down -v` does not delete those directories, but can remove anonymous volumes. Back up both directories before upgrades; image rollback alone does not reverse a database migration. See [backup procedure](../operations/upgrades.md).

The image's web worker uses www-data (UID 33); host directory provisioning initially uses littledog. Confirm effective ownership before repairs. `FS_METHOD=direct` permits direct writes but does not fix permissions. After confirming the image user and affected path, restore WordPress ownership on its HTML tree; do not apply that UID to the database. The DB uses its own image-managed user.

## Operations

```bash
loft-ctl rebuild pupyrus
loft-ctl health pupyrus
sudo docker compose -f /srv/the-loft/services/pupyrus/docker-compose.yml \
  --profile cli run --rm cli wp plugin list
sudo docker compose -f /srv/the-loft/services/pupyrus/docker-compose.yml \
  --profile cli run --rm cli wp cache flush
```

Use the CLI image, not `docker exec pupyrus wp ...`. [Service setup](../../services/pupyrus/setup.sh) checks whether WordPress is installed and initializes it with adminhabl if needed. It currently bootstraps the URL as `http://localhost`; verify the site's canonical URL in WordPress after first installation.

A changed GraphQL JWT secret invalidates existing tokens; clients must authenticate again. For cache issues, inspect Redis activity and whether the object-cache plugin is enabled before deleting cache files.

## Database incident and recovery

**Recorded 2026-07-27:** repeated `Bad magic header in tc log` errors were attributed to unclean MariaDB shutdown during daemon restarts. The retained mitigation is `stop_grace_period: 60s` in Compose and `shutdown-timeout: 90` in [daemon.json](../../daemon.json). Earlier notes blamed setup recreation; a future recurrence needs fresh evidence.

1. Capture `sudo docker logs pupyrus-db --tail 100`, container state, disk space and ownership. Confirm the installed daemon configuration and when Docker last restarted; repository edits alone do not change the running daemon.
2. Stop the affected group and make a cold copy of its existing data before any repair. Preserve the original logs and image version.
3. Separate an upgrade-required error from transaction-log or InnoDB corruption. `MARIADB_AUTO_UPGRADE` is not an InnoDB corruption-recovery mode.
4. Follow the database/version-specific recovery procedure or restore a known-good backup. Do not infer that `tc.log` contains nothing important merely because WordPress does not issue XA transactions; MariaDB also has internal coordination.
5. Start the group, wait for the DB and Redis healthchecks, and verify actual WordPress reads/writes.

References: [MariaDB internal XA](https://mariadb.com/docs/server/reference/sql-statements/transactions/xa-transactions), [InnoDB recovery modes](https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-troubleshooting/innodb-recovery-modes). WordPress depends on healthy DB/Redis at startup; a running web container alone does not prove the database is usable.
