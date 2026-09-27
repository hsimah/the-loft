# Clog on Viking

Updated 2026-09-27. The former WordPress proposal is superseded by the standalone
Nginx + PHP-FPM + SQLite application. The public hostname is
`clog.loft.hsimah.com`; routes start at `/`.

The implementation and ordered operator commands are in the
[Clog runbook](../docs/services/clog.md). Configuration is prepared locally;
Viking and Cloudflare have not been changed by this work.

## Remaining rollout

1. Select the final verified standalone archive and independently recorded checksum.
2. Stage it on Viking, prepare private writable data and create the first account.
3. Start the private Nginx/FPM service and verify it through existing Caddy ingress.
4. Confirm Cloudflare edge certificate coverage, then add the exact hostname to
   `viking-prod` and verify proxied DNS/cache behavior.
5. Apply the LAN DNS exception on space-needle and test cellular/LAN use.
6. Rehearse off-host backup restoration, record capacity/isolation checks and verify
   reboot recovery before treating the installation as complete.

The app still needs an account recovery/reset operation; the current CLI can
create accounts. Automated off-host backup transport and monitoring also remain
operator setup work. These are explicit production follow-ups, not deployed features.
