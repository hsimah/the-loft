# Host provisioning

[setup.sh](../../setup.sh) runs as root on Debian/Ubuntu and loads `hosts/$(hostname)/host.conf`. Use [Pi provisioning](../operations/raspberry-pi.md) or [Calavera reimage](../operations/calavera-reimage.md) for fresh hardware.

```bash
cd /srv/the-loft
sudo bash setup.sh
```

## Inputs and effects

| Input | Effect |
|---|---|
| Hostname | Selects host.conf; unknown hosts fail before provisioning |
| Storage fields | Adds a missing fstab device entry and mounts the configured filesystem; does not format disks |
| User/group fields | Creates pack-member/littledog as GID/UID 1003 if absent; preserves existing IDs; adds configured groups |
| SSH fields | Restricts SSH to adminhabl and optionally disables password authentication |
| CONFIG_DIRS / MEDIA_DIRS | Creates directories; resets their top-level ownership to littledog:pack-member and modes to 755/775 |
| SERVICES and service environments | Runs Compose with host overrides; skips deployment when an expected `.env` is missing |
| Per-service setup scripts | Sources them after service deployment; currently WordPress initialization and torrent-cleanup cron |
| Optional host bootstrap | Sources `hosts/<hostname>/bootstrap`; Calavera installs/configures the dashboard and hardware workarounds |
| Wi-Fi fields | Installs watchdog script, defaults file and cron; see [Calavera](../hosts/calavera.md) for firmware recovery |
| DEPLOY_TARGETS | Replaces `/etc/cron.d/loft-deploy-*` with the configured hourly release jobs |

The script also installs base packages (including terminal definitions), activates tracked Git hooks, installs Docker if missing, creates `loft-proxy`, and copies daemon.json. Changing daemon.json restarts Docker. Git hooks update `.deployed-version` after checkout/merge; that marker records checkout state, not proof every container was redeployed.

## Re-running and managed files

Provisioning is repeatable but has side effects. It **overwrites** adminhabl's `.bashrc` and `.inputrc` with includes of the repo's `bashrc.d` and `inputrc.d`. Back up local customizations before adopting those files. It rewrites SSH/sudoers configuration and validates the generated sudoers file.

Directory provisioning does not establish every container's runtime UID. Images have their own users; WordPress ownership differs from the host convention. See [Pupyrus](../services/pupyrus.md) and verify actual mount ownership before changing existing data.

The script starts declared services but does not stop ones removed from the manifest. It does not automatically rewrite an existing fstab entry when a device setting changes. Calavera's bootstrap purges unwanted desktop/laptop packages and masks sleep targets; inspect it before repurposing that host.

Re-run after changes to host directories, groups, cron, installed watchdog/bootstrap scripts, managed dotfiles or daemon settings. Routine application configuration normally needs only [loft-ctl](loft-ctl.md). Fill skipped `.env` files from their examples and rerun the necessary setup/deployment steps.

## Verification

Keep an existing SSH session open while verifying a fresh host's key login and sudo access. Check `sudo sshd -T`, `id littledog`, mounts, installed cron, and `loft-ctl health`. A setup completion summary is not an application acceptance test.

For a Docker restart failure, inspect `sudo journalctl -u docker --since '5 min ago'` and the installed `/etc/docker/daemon.json`. Editing the repo's copy alone does not update the installed file. Do not launch a second daemon as a generic diagnostic.
