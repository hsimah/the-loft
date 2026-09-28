# Clog on Viking

Updated 2026-09-27. Standalone Nginx + PHP-FPM + SQLite now serves
`clog.hsimah.com`. The operator verified LAN/cellular access, login and persistent
writes across devices. See the [Clog runbook](../docs/services/clog.md).

`loft-ctl deploy clog` automates installation and release updates from the checked-in
pin. It has local failure/retry coverage; first live invocation remains pending.
Cloudflare routing stays a manual first-cutover step and is already configured.

## Remaining operations

- Rehearse encrypted off-host backup restoration and arrange scheduled backups.
- Revisit memory-controller support and reboot acceptance when the operator is ready.
- Measure capacity and repeat isolation checks for the running app.
- Add account reset/recovery support in the app; the current CLI creates accounts.
