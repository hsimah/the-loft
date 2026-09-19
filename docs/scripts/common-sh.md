# Shared Compose and health helpers

[common.sh](../../control-plane/common.sh) is sourced by setup and loft-ctl. Sourcing enables `set -euo pipefail`, loads `hosts/$(hostname)/host.conf`, and exits if the host is unknown. Use a subshell for ad-hoc inspection so those settings do not affect your interactive shell.

| Function | Contract |
|---|---|
| `compose_args_for service` | Emits `-f` arguments for the base file and existing host override; fails if base is absent |
| `check_containers args service` | Resolves active services with `compose config --services`, then polls all containers for running state and healthy Docker healthchecks where defined |
| `check_url url tier [warn_only]` | Five-second curl probe; transport failure fails unless warn-only; any HTTP status is accepted |
| `check_endpoint label [warn_only]` | Runs defined local/lan/ssl URLs for a label; returns failure count |
| `check_web_ui service` | Reads required/warn-only endpoint labels from host.conf and runs their probes |

Container checks poll every 5 seconds for up to 30 seconds. Inactive profiles, including Pupyrus's one-shot CLI, are excluded. Missing active services, stopped containers and starting/unhealthy Docker healthchecks fail after the timeout. Caddy's Docker healthcheck probes its container-local admin API; no host port is needed.

URL checks use `curl -k`: `ssl` means an HTTPS route was reached, not that its certificate is trusted. HTTP 401/403, login pages and HTTP 500/502 all count as responses. These are reachability checks, not application acceptance tests or VPN verification. Warn-only failures are reported without failing the command.

## Configuration

`SERVICE_ENDPOINTS` and `SERVICE_ENDPOINTS_WARN` map each service to space-separated labels. `HEALTH_URLS` and `HEALTH_URLS_WARN` map `label:tier` to a URL. Missing tiers are skipped. See [space-needle's manifest](../../hosts/space-needle/host.conf) for actual endpoints.

```bash
(cd /srv/the-loft; source control-plane/common.sh; compose_args_for houstn)
```

The result deliberately relies on shell word splitting; callers use `docker compose ${compose_args} ...`. Checkout paths with spaces are not supported by this interface. The helper does not read service secrets itself; Compose resolves each service environment.

Behavior checks run with `python3 -m unittest discover -s tests` without Docker or network access. For operational checks use [loft-ctl](loft-ctl.md), then verify the application itself.
