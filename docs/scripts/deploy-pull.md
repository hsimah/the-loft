# Static-site release deployment

[deploy-pull.sh](../../control-plane/deploy-pull.sh) downloads the single `.tar.gz` asset from a repository's latest GitHub Release and syncs it into a host directory. Setup installs one hourly root cron job per `DEPLOY_TARGETS` entry. [Pawst](../services/pawst.md) consumes these directories.

```text
name|owner/repo|target_dir|optional_post_hook
```

The CLI accepts those four fields, optionally followed by an explicit release tag and lowercase SHA256. Both are required together. Explicit tags select `/releases/tags/<encoded-tag>` and support older-release rollback; omitting both retains legacy latest behavior on non-production hosts. A host manifest with `PRODUCTION_ROLE=true` requires both. It calls [github-app-token.sh](github-app-token.md) for optional authentication, fetches release metadata, compares the tag with `/var/lib/loft/deploy/<name>.version`, downloads/extracts a changed release into a sibling staging directory, verifies the requested checksum before safe extraction, then uses `rsync -a --delete` into the target.

**The target directory is not replaced:** keeping its inode preserves the running container's bind mount. Syncing individual files is not an atomic whole-site swap. The script sets staging ownership to littledog:pack-member where possible and gives files/directories appropriate read/traverse permissions.

## Release contract and state

- Publish one deployable `.tar.gz` asset, either a flat tree or a single wrapper directory. Ambiguous multiple matching assets are rejected. Static releases must contain index.html; links, special files, traversal and expanded trees above 512 MiB are rejected before syncing.
- The `/releases/latest` API selects the release; drafts/prereleases are not a deployment mechanism here.
- An unchanged tag skips legacy deployment; pinned deployment also compares the recorded checksum. A changed checksum forces a verified download.
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

To recover missing/corrupt content at the same tag, run the puller with
`sudo env LOFT_FORCE_DEPLOY=1 ...` and the approved tag/checksum. This bypasses
only the state-based skip; the normal lock, checksum and extraction checks
still apply. Viking's [restore script](../../hosts/viking/restore) uses this path. A per-target nonblocking lock rejects concurrent manual/cron deployment. Different names must never point at the same target. To roll back, provide the previous known-good tag and SHA256 as the fifth and sixth CLI arguments. Disable latest-release cron first so it cannot undo the rollback. Viking deliberately has no latest-release cron; see the [platform runbook](../operations/application-platform.md).

## Troubleshooting

Check the selected tag and asset, available disk space in `/tmp` and the target filesystem, and the App installation's repository access. A failed hook is separate from a failed sync. A leftover `.deploy.*` directory may belong to a running invocation; confirm no deploy is using it before deleting it.

Root-owned readable static files are not inherently unreadable by nginx. On permission errors, inspect traversal/read permissions on the actual path rather than assuming all files must have one owner.

The puller requires Python 3 and flock (util-linux), installed by setup. State also records `<name>.sha256`. Retain release archives independently; a checksum detects changed bytes but cannot restore a deleted GitHub asset.
