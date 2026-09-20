# loft-ctl

[loft-ctl](../../loft-ctl) manages the services declared for the local hostname. The shell alias in [bashrc.d](../../bashrc.d) resolves the checkout, so no particular working directory is required.

| Command | Behavior |
|---|---|
| `start <services> / --all` | Compose `up -d` |
| `stop <services> / --all` | Compose `down`, without deleting volumes |
| `rebuild <services> / --all` | `down`, `pull`, then `up -d --build`; no health check |
| `health [services]` | Container and URL checks; defaults to all declared services |
| `update <services> / --all` | Fetch, checkout, fast-forward pull, rebuild and health checks |

`update --branch <name>` selects a branch (default `main`). `update --no-pull` skips Git. Other mutating commands require explicit targets. There is no `reload` command; use the application's own reload operation, such as the Caddy command in [Mushr](../services/mushr.md).

```bash
loft-ctl health
loft-ctl rebuild howlr
loft-ctl health howlr
loft-ctl update --no-pull mushr
```

## Privileges and configuration

The usual SSH account is `adminhabl`, which can run Docker. Invoked as another user, the script uses `su - adminhabl`; non-root callers may be asked for that account's password each invocation. For update, Git runs as the original caller before switching users. Normal adminhabl operation needs that user's Git access.

The script reads `hosts/$(hostname)/host.conf` and uses [common.sh](common-sh.md) to merge any host override. Profiles come from each service environment. An unknown host or service fails; `--all` means this host's manifest, not the entire fleet.

## Important limits

- Rebuild stops a group **before** downloading/building. Pull/build first for large images or the ingress proxy; see [upgrades](../operations/upgrades.md).
- Pull errors are currently suppressed so locally built Caddy can be rebuilt. A successful rebuild can therefore reuse an already cached image after a registry failure. Verify actual image/version after upgrades.
- Health checks have a 30-second container readiness window and limited URL semantics; see [the health contract](common-sh.md).
- Adding a service may require setup for directories or cron. Removing one from `SERVICES` does not stop its existing containers: stop it before removing the entry.
- Provisioning scripts copied into `/usr/local/bin` are refreshed by setup, not by `loft-ctl update`.

If Git update fails, inspect `git -C /srv/the-loft status` and resolve local changes before retrying. If the script switches users unexpectedly, confirm you logged in as adminhabl. Do not use fleet-wide rebuilds as the first response to a single failed service.

## Production role

Viking start/rebuild/update requires `/etc/loft/dmz-ready`; follow the [platform runbook](../operations/application-platform.md) first. Production promotion uses reviewed artifact pins and merged Compose pull/up for controlled changes. `update` still pulls a branch and rebuild performs down/up; neither is an atomic release deployment. Enable Viking tunnel deliberately with `COMPOSE_PROFILES=public` in Mushr’s ignored `.env`.
