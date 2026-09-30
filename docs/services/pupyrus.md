# Pupyrus — WordPress

[Compose](../../services/pupyrus/docker-compose.yml) runs WordPress/Apache (`pupyrus`), MariaDB and Redis on space-needle. Only WordPress joins `loft-proxy`; no host port. Access via `https://pupyrus.loft.hsimah.com`. The `cli` profile runs one-shot WP-CLI.

## Configuration and data

[.env.example](../../services/pupyrus/.env.example): DB and admin credentials, table prefix, GraphQL JWT secret (changing it logs out all clients). Enable Redis Object Cache in WordPress settings.

| Host path | Data |
|---|---|
| `/opt/pupyrus/html` | WordPress code, plugins, themes, uploads (owned by www-data, UID 33) |
| `/opt/pupyrus/db` | MariaDB data (image-managed user) |

Back up both before upgrades; image rollback does not undo DB migrations. Never apply the WordPress UID to the DB directory.

## Operations

```bash
loft-ctl rebuild pupyrus
sudo docker compose -f /srv/the-loft/services/pupyrus/docker-compose.yml \
  --profile cli run --rm cli wp plugin list
```

Use the CLI container, not `docker exec pupyrus wp`. [setup.sh](../../services/pupyrus/setup.sh) installs WordPress as adminhabl with URL `http://localhost`; fix the site URL after first install.

## Database errors

`Bad magic header in tc log` came from MariaDB being killed during Docker restarts. Mitigation: `stop_grace_period: 60s` in Compose and `shutdown-timeout: 90` in [daemon.json](../../daemon.json).

For any DB error: capture logs, stop the group and take a cold copy **before** repairing. `MARIADB_AUTO_UPGRADE` is not corruption recovery, and don't delete `tc.log` on the assumption it's unused. Follow MariaDB's [recovery modes](https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-troubleshooting/innodb-recovery-modes) or restore a backup, then verify real reads/writes.
