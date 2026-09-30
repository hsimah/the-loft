# loft-ctl

[loft-ctl](../../loft-ctl) manages services declared in `hosts/$(hostname)/host.conf`. The [bashrc.d](../../bashrc.d) alias works from any directory.

| Command | Behavior |
|---|---|
| `start <services> / --all` | Compose `up -d` |
| `stop <services> / --all` | Compose `down` (volumes kept) |
| `rebuild <services> / --all` | `down`, `pull`, `up -d --build`; **no health check** |
| `health [services]` | Container and URL checks ([contract](common-sh.md)) |
| `update <services> / --all` | Git fetch + fast-forward (`--branch`, default `main`; `--no-pull` skips), rebuild, health |
| `deploy clog [--plan]` | Pinned [Clog](../services/clog.md) install/update on Viking |

`--all` means this host's manifest, not the fleet. There is no `reload`; use the app's own (e.g. Caddy in [Mushr](../services/mushr.md)).

## Limits

- Rebuild stops the group **before** pulling/building. Pull first for large images or Caddy.
- Pull errors are suppressed (so local Caddy can rebuild), so a rebuild can silently reuse a cached image. Check the running version after upgrades.
- Removing a service from `SERVICES` doesn't stop it; stop it first.
- On Viking, start/rebuild/update require `/etc/loft/dmz-ready`. Precise production rollouts use merged Compose directly; see the [application platform](../operations/application-platform.md#adding-an-application).
- Run as `adminhabl` (in the Docker group). It does not switch users.
