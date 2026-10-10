# deploy-pull.sh

[deploy-pull.sh](../../control-plane/deploy-pull.sh) downloads a GitHub Release's single `.tar.gz` asset and rsyncs it into a directory. Used by [Pawst](../services/pawst.md) through `pawst-deploy.sh`, which supplies GitHub's digest for the chosen tag, and directly on Fjord.

```bash
sudo /srv/the-loft/control-plane/deploy-pull.sh <name> <owner/repo> <target_dir> <post_hook|''> <tag> <sha256>
```

- Always pinned: it fetches exactly that tag and verifies the checksum. An older tag rolls back.
- The archive is extracted safely (no links, special files, traversal or >512 MiB) and must contain `index.html`.
- `rsync -a --delete` into the existing target keeps its inode, so container bind mounts survive. It is not atomic.
- State: `/var/lib/loft/deploy/<name>.version` and `.sha256`. An unchanged tag+checksum is skipped; `LOFT_FORCE_DEPLOY=1` forces a refetch.
- A per-target lock rejects concurrent runs. Never point two names at one target.
- Auth via [github-app-token.sh](github-app-token.md); if that fails it silently falls back to anonymous, so a private repo shows up as 404.
- A failed post-hook is logged, not retried.

Leftover `.deploy.*` staging dirs may belong to a running deploy; check before deleting.
