# image-updates.sh

[image-updates.sh](../../control-plane/image-updates.sh) lists newer registry tags for every pinned image in the repo: Compose `image:` lines and Dockerfile `FROM` lines (ARG defaults expanded). Run it locally from a checkout; it makes anonymous Docker Hub/GHCR queries and changes nothing.

```bash
control-plane/image-updates.sh      # pins with updates
control-plane/image-updates.sh -a   # every pin
```

- Candidates share the pin's tag shape: `1.30.4-alpine` is compared with `1.31.7-alpine`, never `-bookworm`.
- `minor`/`major`: newest tag sharing the pin's first two/first number. Use these for held lines (nginx stable, Uptime Kuma 1.x).
- Tags that start with a commit hash (LazyLibrarian) are ordered by Docker Hub push date. Other tags use version sort, so linuxserver `-lsN` counter resets are harmless.
- Digest pins report `digest moved` when the tag's current digest differs.
- Local builds (`howlr-snapclient`, `mushr-caddy`) show `?`; their bases are checked through the Dockerfile.

The output does not account for [held pins](../operations/upgrades.md#rollback-and-pin-exceptions) or upgrade paths.
