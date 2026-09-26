# ladygrey

**Configuration prepared, not provisioned.** Agent development host and unattended Immich photo
frame on the owner's
Surface Pro 3, Core i5 with 8 GB RAM. SSD capacity, exact CPU model and reserved
network address remain to be recorded. This is separate from Calavera and Woodstock.

Install **Debian 13 trixie amd64**, stock kernel, SSH and standard utilities,
then add Xorg, i3, LightDM and Firefox ESR for a fullscreen photo kiosk, without
a full desktop environment. Start without linux-surface; verify actual hardware/firmware
support during installation and add a custom kernel only for a specific need.
The [Ladygrey implementation plan](../../plans/ladygrey-development-runner.md)
contains sources, hardware checks and the provisioning sequence.

Claude initially, and Codex later, will run natively on Ladygrey. Docker supplies
Clog/Toroid application and test environments. There is no VM layer. Start with
one job at a time, selected from GitHub issue labels by local cron, and publish
draft PRs after validation. The runner has a native execution adapter; intake remains disabled pending
onboarding and live validation.

The photo display runs under a separate unprivileged account, using a local
Immich Kiosk service and a selected album. Auto-login, browser relaunch and
network recovery should require no physical interaction. Keep its credentials
separate from agent jobs. The kiosk and job environments have independent
lifecycles; display scheduling must not suspend the host. Confirm Immich's URL,
version and album before configuring the service.

Ladygrey is an internal development host with Internet access, restricted LAN
egress and selected inbound management/monitoring. Allow one specific Immich
endpoint for the photo kiosk. It is not a public production/DMZ host like Viking.
No tunnel, public port forwarding or production storage
mounts are planned. Address/interface discovery and firewall design precede
unattended execution; no network isolation has been configured by this document.

Plan for Snoot and Houstn/Glances monitoring, administrative key-only SSH and
AC-powered operation without idle suspend. The fleet manifest, bootstrap, kiosk and runner configuration are available in
[the provisioning runbook](../operations/ladygrey-setup.md). Fjord remains monitoring-only while its next
purpose is chosen; space-needle does not run agent jobs.
