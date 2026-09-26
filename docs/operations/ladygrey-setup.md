# Ladygrey provisioning

**Repository configuration prepared; no live provisioning yet.** Install Debian
13 amd64 with SSH and standard utilities on the Surface Pro 3. Use hostname
`ladygrey`. Start with the stock kernel and test storage, network, display,
charging and thermals. Record its SSD, interface and reserved address.

## Base setup

Use the normal fleet checkout at `/srv/the-loft`. Test the operator's SSH key in
another session before running setup (it disables password authentication).
Prepare `services/snoot/.env` using its example and the Beszel hub's Add System
values. Prepare `services/houstn/.env` with `COMPOSE_PROFILES=metrics`.
Ladygrey's override prevents hub containers even if profiles are stale.

Run on Ladygrey:

```sh
cd /srv/the-loft
sudo bash setup.sh
sudo reboot
```

The [manifest](../../hosts/ladygrey/host.conf) selects Snoot, Houstn and Pupshow.
The [bootstrap](../../hosts/ladygrey/bootstrap) installs i3/LightDM/Firefox,
creates `agentdev`, installs the runner/service and seeds operator configuration
only when absent. It preserves credentials and local enablement on repeat runs.
It does not install linux-surface, guess an interface or change live networking.
The Wi-Fi watchdog uses a nonexistent interface until hardware is recorded.

The display auto-logs in as `rodnik`. It shows a local waiting page until Pupshow
is available. AC lid closure and idle do not suspend; battery lid closure retains
suspend behavior. Verify low-battery behavior on the real unit. Reboot applies
LightDM and logind configuration; setup does not restart the active login session.

## Photos (Pupshow)

Pupshow wraps the community [Immich Kiosk](https://docs.immichkiosk.app/installation/).
Current upstream docs require Immich 3.2.0+. Confirm the server version and choose
a compatible pinned image tag/digest before enabling the service.

Copy `services/pupshow/.env.example` to `.env` and fill the image, exact Immich URL
and curated album ID. Use a separate Immich account with access only to intended
photos where supported, and the release's required API permissions. Album filters
alone do not scope credentials. Save the key on Ladygrey at
`/etc/loft/pupshow/immich-api-key`, owned by root with mode 600; never commit it.
Then run `sudo loft-ctl start pupshow`. Setup skips Pupshow while required values
are missing, so base provisioning can happen first.

Pupshow listens only on `127.0.0.1:3000`. Firefox uses its own profile and restarts
on exit. Test Immich outage/recovery as well as a local service restart. Still
photos, one-minute slides and hidden controls are configured. A night schedule
is optional future configuration; currently the panel remains on. The waiting
page is not an offline photo cache. Neither account separation nor loopback
makes the displayed photos private from arbitrary native host code.

## Network and monitoring

The [firewall template](../../hosts/ladygrey/network/policy.nft.example) is not
installed or applied automatically. Fill the admin, monitoring, DNS, NTP and
Immich sets; add every real LAN/VPN prefix, including globally routed IPv6 LAN
prefixes, to the blocked sets. The template uses IPv4 service exceptions; add
explicit IPv6 exceptions if those services use IPv6. Review against the actual
Docker mode and interface. It allows public HTTPS, not arbitrary Internet ports;
configure apt mirrors for HTTPS or explicitly permit needed update destinations.

Apply only from a recovery-capable console after `sudo nft -c -f <reviewed-file>`
and arrange rollback. Integrate the reviewed table into boot-time nftables
configuration without flushing Docker's tables. Test again after reboot and a
Docker restart. Test allowed SSH/metrics/Immich and blocked LAN access from native
processes and application containers. Private per-job bridge traffic needs its
own narrow rules in this baseline. Rootless Docker is preferred for `agentdev`;
install/configure it under that account and enable its user daemon at onboarding.
Never add `agentdev` to the rootful Docker group. Root-managed fleet containers
remain separate. A host-wide Immich allowance currently also permits agent
traffic to that endpoint; use service-specific egress rules if that distinction
is required. Shared reverse-proxy IP/port allowances cover other virtual hosts.

On space-needle:

- Add `ladygrey` to LAN DNS with the reserved address; verify resolution from
  the Homepage container. No guessed `/etc/hosts` mapping is checked in.
- In Beszel, add system `ladygrey`, its address and port 45876, and copy its
  connection values to Ladygrey's Snoot environment. Verify metrics arrive.
- Homepage's Fleet card is already configured for `http://ladygrey:61208/api/4/all`.
  It will report unavailable until DNS and Ladygrey are ready. Apply the Houstn
  configuration through the usual deployment workflow when ready.
- In Uptime Kuma, add a TCP monitor for Ladygrey port 45876 and an HTTP monitor
  for `http://ladygrey:61208/api/4/status`. Verify that endpoint on the installed
  Glances version; use `/api/4/all` if necessary. Do not expose the photo kiosk
  to the LAN just to monitor it; Docker provides its local healthcheck.

Beszel/Kuma database entries require live UI onboarding; YAML alone cannot
register the new system. Homepage and Beszel hubs stay on space-needle.

## Native agent onboarding

The installed `/etc/loft/dev-runner/config.json` starts with `enabled: false` and
`prompt_approved: false`. It registers `hsimah/clog` and
`hsimah-services/toroid`, accepts only issues authored by `hsimah`, and requires
`agent:ready` plus `agent:claude`. Codex is not implemented yet.

1. As `agentdev`, install a selected Claude Code release using the official
   installation procedure, authenticate with the chosen subscription/API method,
   and run a small headless smoke test. The runner uses that account's persisted
   login. Authenticate `gh` with access only to the two repositories and configure
   Git HTTPS authentication with `gh auth setup-git`.
2. Set the real commit email. Review the starter prompt in
   `/etc/loft/dev-runner/prompt.md`; put each project's actual preparation and
   required validation commands into its JSON argv arrays. Empty checks block
   execution. Install the matching project toolchains and rootless Docker.
   Preparation/check commands run in the job checkout; use per-job Compose
   projects and synthetic data. Set teardown commands to remove that job's
   services without touching the kiosk or other jobs.
3. After network validation, record completion with
   `sudo touch /etc/loft/dev-runner/network-reviewed`. This is an operator record,
   not an automated assertion of firewall correctness. Set `prompt_approved`
   and `enabled` true only after these steps are complete.
4. Create the repository labels: `agent:ready`, `agent:claude`, `agent:running`,
   `agent:review`, `agent:blocked`, `agent:cancel` (and reserve `agent:codex`).
   Label mutations and PR publication require appropriate GitHub permissions.
5. Clone reference projects and inspect intake without modifying GitHub:

   ```sh
   sudo -iu agentdev loft-dev-runner --config /etc/loft/dev-runner/config.json init-repos
   sudo -iu agentdev loft-dev-runner --config /etc/loft/dev-runner/config.json poll
   ```

6. Run one small labelled issue with `sudo systemctl start loft-dev-runner`.
   Inspect `sudo journalctl -u loft-dev-runner` and `/srv/agent-dev/jobs`.
   Require a correct draft PR and valid checks before uncommenting the cron
   entry in `/etc/cron.d/loft-dev-runner`. The five-minute cron starts the same
   service, so overlapping ticks do not spawn concurrent jobs.

The service limits memory to 6 GB with pressure starting at 5 GB and lowers CPU
priority; these are starting values to measure with the photo display active.
Rootless Docker daemon resources are outside that service cgroup: set per-app
limits too. Each invocation runs at most one job. No automatic retries occur.

For immediate cancellation use `sudo systemctl stop loft-dev-runner`; adding
`agent:cancel` is also checked during native commands and before publication.
Disable cron to stop intake. Stop the service before `recover <job-id>`; the
systemd cgroup removes descendants, and recovery preserves the checkout.
`publish <job-id>` retries publication of an unchanged validated commit;
`requeue <job-id>` permits an explicitly retried blocked issue. Invoke these
subcommands as `agentdev` with the same `--config` argument. Retention is manual
until an owner-aware cleanup policy is implemented; do not blanket-prune Docker.

Test cancellation, timeout, reboot, duplicate intake, check failures and network
failure after PR creation before unattended use. Native execution shares the
agent account's credentials and is not a disposable sandbox.
