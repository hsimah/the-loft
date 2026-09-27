# Clog on Viking

Updated 2026-09-27. The former WordPress proposal is superseded by the standalone
Nginx + PHP-FPM + SQLite application. The public hostname is
`clog.hsimah.com`; routes start at `/`.

The implementation and ordered operator commands are in the
[Clog runbook](../docs/services/clog.md). The private service is running on Viking; the hostname correction and Cloudflare
cutover are pending. See the operator rollout record in the runbook.

## Remaining rollout

1. Apply the `clog.hsimah.com` hostname correction and repeat the private health check.
2. Confirm the existing edge certificate is active, then add the exact hostname
   to `viking-prod` and verify proxied DNS/cache behavior.
3. Test cellular/LAN use; the hostname needs no LAN DNS exception.
4. Rehearse off-host backup restoration, record capacity/isolation checks and verify
   reboot recovery. The operator has deferred the memory-controller boot change
   and reboot while bringing up the web app.

The app still needs an account recovery/reset operation; the current CLI can
create accounts. Automated off-host backup transport and monitoring also remain
operator setup work. These are explicit production follow-ups, not deployed features.
