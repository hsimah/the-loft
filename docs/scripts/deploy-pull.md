# Static-site release deployment

[deploy-pull.sh](../../control-plane/deploy-pull.sh) downloads the first `.tar.gz` asset from a repository's latest GitHub Release and syncs it into a host directory. Setup installs one hourly root cron job per `DEPLOY_TARGETS` entry. [Pawst](../services/pawst.md) consumes these directories.

```text
name|owner/repo|target_dir|optional_post_hook
```

The CLI accepts the same four fields as separate arguments. It calls [github-app-token.sh](github-app-token.md) for optional authentication, fetches release metadata, compares the tag with `/var/lib/loft/deploy/<name>.version`, downloads/extracts a changed release into a sibling staging directory, then uses `rsync -a --delete` into the target.

**The target directory is not replaced:** keeping its inode preserves the running container's bind mount. Syncing individual files is not an atomic whole-site swap. The script sets staging ownership to littledog:pack-member where possible and gives files/directories appropriate read/traverse permissions.

## Release contract and state

- Publish one deployable `.tar.gz` asset, either a flat tree or a single wrapper directory. Additional matching assets make selection ambiguous; the first is used.
- The `/releases/latest` API selects the release; drafts/prereleases are not a deployment mechanism here.
- An unchanged tag skips deployment, even if its attached asset changed.
- Cron appends output to `/var/log/loft/deploy.log`. Manual invocations print to the terminal.
- The version marker is written after rsync, before the optional post-hook. Hook failure logs a warning and does not undo deployment or retry it on the next unchanged-tag run.
- If GitHub App token creation fails for any reason, the script falls back to anonymous access. A private repo can consequently appear as a 404; test auth separately.

## Operations

```bash
sudo /srv/the-loft/control-plane/deploy-pull.sh \
  pawst-hblake hsimah-services/hblake /opt/pawst/hblake-html
sudo tail -n 50 /var/log/loft/deploy.log
sudo cat /var/lib/loft/deploy/pawst-hblake.version
```

To add a target, declare its directory in host.conf, add its DEPLOY_TARGETS entry, publish an artifact, and rerun setup to install cron. Use the [GitHub App guide](github-app-token.md) for private repos.

To retry the same tag, remove only that target's version marker and invoke the puller again. Avoid simultaneous manual and cron runs: the script has no locking. To roll back, publish a new release containing the known-good build; there is no CLI argument to select an older tag.

## Troubleshooting

Check the selected tag and asset, available disk space in `/tmp` and the target filesystem, and the App installation's repository access. A failed hook is separate from a failed sync. A leftover `.deploy.*` directory may belong to a running invocation; confirm no deploy is using it before deleting it.

Root-owned readable static files are not inherently unreadable by nginx. On permission errors, inspect traversal/read permissions on the actual path rather than assuming all files must have one owner.
