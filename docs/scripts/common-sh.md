# common.sh

[common.sh](../../control-plane/common.sh) is sourced by setup and loft-ctl. Sourcing sets `set -euo pipefail` and loads the host's host.conf, so use a subshell for ad-hoc use:

```bash
(cd /srv/the-loft; source control-plane/common.sh; compose_args_for houstn)
```

| Function | Contract |
|---|---|
| `compose_args_for service` | `-f` args for base + host override (word-split; no spaces in paths) |
| `check_containers args service` | Every active Compose service must be running and healthy (if it has a healthcheck); polls 5 s for up to 30 s |
| `check_url url tier [warn_only]` | 5 s `curl -k`; any HTTP status passes, transport failure fails |
| `check_endpoint label [warn_only]` | Runs a label's local/lan/ssl URLs |
| `check_web_ui service` | Runs the service's labels from host.conf |

URL checks are reachability only: 401/403/500/502 pass and certificates are not verified. Inactive profiles are skipped.

host.conf maps `SERVICE_ENDPOINTS[_WARN]` (service → labels) and `HEALTH_URLS[_WARN]` (`label:tier` → URL). Tests: `python3 -m unittest discover -s tests`.
