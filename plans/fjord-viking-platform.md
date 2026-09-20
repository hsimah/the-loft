## Goal
Make Fjord the LAN-only dev/test application platform and Viking a replaceable production/DMZ role, with Pawst as its first workload.

## Repository baseline
Space-needle currently owns Pawst, Mushr/Caddy, LAN DNS and a dashboard-managed Cloudflare Tunnel. Applications share loft-proxy. Fjord has metrics only; Viking is still an audio/metrics client awaiting Woodstock cutover. Static releases already pull directly from GitHub but currently track latest and rsync in place. Existing local Woodstock/documentation edits must be preserved.

## Implementation
- Preserve Compose base + host override and loft-ctl conventions. Add host-specific Mushr and Pawst configurations, per-app/environment internal networks, LAN-only Fjord routes, and a production-only Viking route table.
- Use Pawst dev/test on Fjord as a working onboarding pattern. Use version-tagged images, non-root services, read-only roots, writable tmpfs/volumes, bounded resources and logs; no published application ports.
- Extend release-puller with explicit tag and SHA256 selection, safe archive extraction and serialized deployments; keep legacy latest behavior for the existing host during migration. Viking has no latest-release cron.
- Prepare Viking with Pawst/Caddy and an opt-in production tunnel. Preserve old deployment until verified cutover.
- Document lifecycle, promotion/rollback, secrets, backup, replacement hardware, exact ordered DMZ firewall requirements and validation from host AND container namespaces.
- Validate Compose merges, network/security invariants, release failure behavior, shell/Python syntax, existing health tests and documentation links.

## Operator gates (not performed by repository changes)
- Complete Woodstock audio handoff before retiring Viking audio/metrics agents.
- Allocate isolated DMZ VLAN/subnet, forbid Viking-initiated trusted-LAN traffic on IPv4 and IPv6, including container forwarding; permit only documented DNS/NTP/update/tunnel exceptions. Test and record evidence before public cutover.
- Select actual release tags and checksums, verify image architecture support, provision secrets and content on Viking; verify local routes before enabling tunnel.
- Create a separate Viking tunnel with only hbla.ke and hsimah.com. Switch public routes after local verification; verify externally, logs, negative hostname tests and isolation. Preserve old deployment for rollback then explicitly retire old cron/routes/content.

## Acceptance
Fjord dev/test remains private; production deploys known artifacts directly from GitHub without Fjord dependency. Caddy routes do not imply public exposure. Viking can be replaced without changing its role or release model. No claim of live migration or network isolation until operator checks pass.

## Local implementation status

Repository implementation prepared: Fjord dev/test and Viking production host
overrides, opt-in public tunnel, production provisioning attestation, pinned
release/checksum deployment, safe extraction, locking, regression tests and
[operator runbook](../docs/operations/application-platform.md). Space-needle's
legacy deployment remains deliberately intact until cutover.

Local validation: 24 Compose combinations, 22 regression tests, shell/JSON/Python
syntax and documentation links passed. Docker runtime validation could not run:
local socket permission denied and sudo requires an interactive password. CI now
includes Caddy/nginx validation under the configured unprivileged constraints;
that CI job has not been run from this worktree. Subsequent operator-led hardening is recorded in [the live runbook](../docs/operations/viking-hardening.md); public deployment and reboot checks are now complete. Fjord live validation and off-host restore remain pending.

GitHub issue lookup succeeded, but issue creation failed connecting to
api.github.com even with elevated network access. This file is the requested
issue-body fallback, not a claim that a GitHub issue exists.

## Operator steering: retain monitoring

Preserve Snoot and Glances on Viking with space-needle-initiated Tailscale access to TCP 45876/61208 only. Homepage uses a host-specific Tailscale mapping. Woodstock audio handoff is complete; Snapclient is stopped. Setup must not restore littledog Docker membership. Track the tested host firewall, SSH and unattended-update baseline without automatically replacing live files.
