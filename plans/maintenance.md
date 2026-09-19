# Open maintenance work

Repository cleanup completed 2026-09-19; these items require runtime evidence or a separate implementation decision. This list does not assert that a host has already been changed. Baseline: [notes audit](../docs/audits/2026-09-19-notes.md).

| Work | Next evidence/action |
|---|---|
| Sputnik empty-inbox flow | Test empty and populated mail/calendar cases in deployed n8n. Add an explicit empty-mail branch if needed; export and retest. Current JSON is unchanged and the no-items path remains unverified |
| Import/cleanup safety | Check *arr import status, actual inode/link counts and retained library files. Plan a shared-parent mount migration before claiming hardlink support; ratio-based removal does not establish successful import |
| Host identities/device access | Record actual littledog UID/GID, Plex runtime identity and device groups; the Plex example uses 1004 while fresh provisioning uses 1003. Do not chown existing data by inference |
| Pi networking | Confirm manager/unit and interface on Viking/Fjord; watchdog defaults to dhcpcd and may need a host override for NetworkManager |
| Beszel connectivity | Confirm hub-side resolution/reachability and per-system tokens; Homepage host mappings do not apply to Beszel |
| Exposure and OAuth | Check live Cloudflare names, Plex Remote Access/router state and granted Google scopes; these are not fully described in Git |
| Image maintenance | Evaluate maintained Snapclient/VPN replacements without reusing the older nonworking VPN tag; assess pinned application upgrades separately |
| Reproducibility | Pin Caddy's module source in a dedicated tested build change; verify Jackett self-updating behavior |
| Deployment availability | Consider pull/build-before-down in loft-ctl and surfacing registry failures currently suppressed during rebuild |
| Backup/restore | Verify recoverable application data and secrets backups; local tarballs on the same host are insufficient for host loss |
| Oxbow | [Proposed Brisbane replica](../memory/project_oxbow_host.md); confirm actual hardware/deployment before adding a manifest |

Completed locally: curl transport failures no longer pass health; missing/stopped/unhealthy active Compose services fail health; Caddy uses its container healthcheck; active documentation was consolidated and the old provisioning plans archived. Deployment of those code changes has not been performed.
