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

The script also installs base packages (including tmux and terminal definitions), activates tracked Git hooks, installs Docker if missing, creates `loft-proxy`, and copies daemon.json. Changing daemon.json restarts Docker. Git hooks update `.deployed-version` after checkout/merge; that marker records checkout state, not proof every container was redeployed.

## Re-running and managed files

Provisioning is repeatable but has side effects. It **overwrites** adminhabl's `.bashrc`, `.inputrc` and `.tmux.conf` with includes of the repo's `bashrc.d`, `inputrc.d` and `tmux.d`. Back up local customizations before adopting those files. It rewrites SSH/sudoers configuration and validates the generated sudoers file.

Directory provisioning does not establish every container's runtime UID. Images have their own users; WordPress ownership differs from the host convention. See [Pupyrus](../services/pupyrus.md) and verify actual mount ownership before changing existing data.

The script starts declared services but does not stop ones removed from the manifest. It does not automatically rewrite an existing fstab entry when a device setting changes. Calavera's bootstrap purges unwanted desktop/laptop packages and masks sleep targets; inspect it before repurposing that host.

Re-run after changes to host directories, groups, cron, installed watchdog/bootstrap scripts, managed dotfiles or daemon settings. Routine application configuration normally needs only [loft-ctl](loft-ctl.md). Fill skipped `.env` files from their examples and rerun the necessary setup/deployment steps.

Calavera and Woodstock share Surface dashboard provisioning, which installs feh and configures i3 to apply `/home/rodnik/Pictures/wallpaper.webp` on session startup and i3 restart. Supply that image locally on each host, readable by rodnik; setup does not copy the wallpaper. After provisioning an existing session, press `Mod+Shift+r` to apply the updated i3 config.

## Shared tmux

[tmux.d](../../tmux.d) provides mouse support, 50,000 lines of scrollback, windows numbered from 1, splits that inherit the current directory, and a hostname/session status line. The prefix remains `Ctrl-b`; press `Ctrl-b d` to detach.

For existing hosts, adopt just tmux after pulling the repo. Run as `adminhabl`:

```bash
sudo apt-get update
sudo apt-get install -y tmux ncurses-term kitty-terminfo
if [ -e ~/.tmux.conf ]; then
  cp -a ~/.tmux.conf ~/.tmux.conf.backup-$(date +%Y%m%d-%H%M%S)
fi
printf 'source-file /srv/the-loft/tmux.d\n' > ~/.tmux.conf
tmux new-session -A -s loft
```

An already-running server needs `tmux source-file ~/.tmux.conf` to load changes. Existing panes keep their current terminal environment and scrollback limit; new panes receive the updated defaults.

## Verification

Keep an existing SSH session open while verifying a fresh host's key login and sudo access. Check `sudo sshd -T`, `id littledog`, mounts, installed cron, and `loft-ctl health`. A setup completion summary is not an application acceptance test.

For a Docker restart failure, inspect `sudo journalctl -u docker --since '5 min ago'` and the installed `/etc/docker/daemon.json`. Editing the repo's copy alone does not update the installed file. Do not launch a second daemon as a generic diagnostic.

## Production gate

Viking provisioning requires `/etc/loft/dmz-ready` after completing the [application platform network and host checklist](../operations/application-platform.md). This is operator attestation, not automatic firewall configuration. Setup validates merged Compose configuration before starting each service; host overrides can intentionally omit the base service environment file. Python 3 and util-linux support verified release extraction and deployment locking.

On `PRODUCTION_ROLE=true` hosts, setup removes littledog from Docker instead of granting daemon access. Adminhabl retains Docker access. Existing live firewall files are not automatically overwritten; follow the [hardening record](../operations/viking-hardening.md).
