# loft-ctl

[loft-ctl](../../loft-ctl) manages services declared in `hosts/$(hostname)/host.conf`. The [bashrc.d](../../bashrc.d) alias works from any directory.

| Command | Behavior |
|---|---|
| `start <services> / --all` | Compose `up -d` |
| `stop <services> / --all` | Compose `down` (volumes kept) |
| `rebuild <services> / --all` | `pull` (skipping local builds) and `build` while running, then `down`, `up -d`; **no health check** |
| `health [services]` | Container and URL checks ([contract](common-sh.md)) |
| `update <services> / --all` | Git fetch + fast-forward (`--branch`, default `main`; `--no-pull` skips), rebuild, health |
| `setup` | [Provision this host](setup.md); elevates with sudo; no arguments |
| `deploy clog [--plan] [version]` | Latest or given [Clog](../services/clog.md#deploy-and-update) release on Viking |
| `deploy pawst <site> [tag]` | Latest or given [Pawst](../services/pawst.md#deploy-and-roll-back) release on Viking |

`--all` means this host's manifest, not the fleet. There is no `reload`; use the app's own (e.g. Caddy in [Mushr](../services/mushr.md)).

## Limits

- A failed pull or build stops the rebuild and leaves the group running.
- Removing a service from `SERVICES` doesn't stop it; stop it first.
- On Viking, start/rebuild/update require `/etc/loft/dmz-ready`. Precise production rollouts use merged Compose directly; see the [application platform](../operations/application-platform.md#adding-an-application).
- Run as `adminhabl` (in the Docker group). Only `setup` and `deploy` escalate with sudo.
