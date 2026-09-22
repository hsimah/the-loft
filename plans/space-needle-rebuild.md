# Space-needle Debian and storage redesign

Status: **deferred at the operator's request on 2026-09-19; planning only.**
The operator is not proceeding with migration today. This is not an executable
migration runbook. No migration changes have been performed. Target: Debian 13 minimal, retaining the
current service versions during the OS migration. Choose final sizes and a
cutover window after hardware health, backup capacity and restore tests.

## Agreed direction and stopping point

- Prioritize stability, reliability and predictable maintenance. Prefer Debian
  for the proposed rebuild, without treating the Ubuntu coreutils transition as
  proof the current installation is unreliable.
- Use free LVM extents on the existing SSD; no spare SSD is available. Retain
  Ubuntu as a bootable fallback and preserve the D5-300 RAID5/XFS volume.
- Separate OS, container storage, persistent application state and disposable
  scratch space. The sizes below are proposals, not final allocations.
- Leave the approximately 828 GiB of VG free space unallocated for now. The
  earlier suggestion to grow Ubuntu root to 250 GiB was not reported executed;
  do not assume that resize happened or consume the planned Debian space.
- Docker build-cache and unused-image cleanup were completed by the operator.
  Final post-image-cleanup capacity and hardware health remain unverified.
- Resume with read-only inventory and backup planning, not partition creation,
  formatting, package upgrades or service cutover.

## Evidence from operator checks (2026-09-19)

- Internal CT1000P3PSSD8 NVMe: 931.5 GiB, 928.46 GiB LVM PV/VG;
  root LV 100 GiB, about 828.46 GiB free in the VG.
- Existing SSD partitions: `nvme0n1p1` 1 GiB FAT EFI, `nvme0n1p2`
  2 GiB ext4 `/boot`, `nvme0n1p3` 928.5 GiB LVM. Ubuntu root is ext4
  at `/dev/ubuntu-vg/ubuntu-lv`. Root inode use was 26%; array inode use 1%.
- Root reached 90% with 84 GiB used. Build cache cleanup reduced that to
  68 GiB / 74%; unused images were subsequently removed (final usage pending).
- Before cleanup: Docker images 34.91 GB, build cache 12.73 GB, `/opt` 18 GiB,
  Plex state 11 GiB, Howlr state 3 GiB, journals 2.6 GiB.
- Operator identified the enclosure as TerraMaster D5-300 (not D5-300C).
  USB device identifies as `TDAS RAID5`, 72.8 TiB; XFS `/mammoth` has about
  14 TiB used and 59 TiB available. No Linux md arrays are assembled.
- SMART, individual RAID member health, controller status and backup restore
  verification remain outstanding. Filesystem usage is not evidence of health.
- `smartctl` was not installed when checks were requested. Installation of
  `smartmontools` was suggested, but no installation or SMART output was supplied.

## OS recommendation

Debian 13 is a good fit for a minimal container host and aligns with the Surface
clients. Ubuntu LTS is also a supportable choice; this is a preference for the
host's release policy, not evidence Ubuntu caused the disk pressure. Debian
does not stabilize independently updated container applications automatically.

Debian lists full support through August 2028 and LTS through June 2030.
Canonical's April 2026 coreutils update says Ubuntu 25.10 adopted rust-coreutils
and 26.04 retained GNU `cp`, `mv`, and `rm`. Confirm the installed Ubuntu release
before attributing any of those changes to this server.

Sources: [Debian lifecycle](https://www.debian.org/releases/trixie/index),
[Ubuntu coreutils update](https://discourse.ubuntu.com/t/an-update-on-rust-coreutils/80773),
[Ubuntu support lifecycle](https://ubuntu.com/about/release-cycle).

## Proposed internal SSD layout

No spare SSD is available. Preferred revised approach: retain Ubuntu's existing
100 GiB root LV and create new Debian LVs in the approximately 828 GiB of free
extents in `ubuntu-vg`. This free space is inside the existing LVM partition;
there is no need to shrink Ubuntu or repartition the physical SSD.

Keep the VG name during migration. Use manual installer partitioning only;
never select guided whole-disk LVM or recreate the existing PV/VG. Format only
new Debian volumes. Preserve Ubuntu's separate `/boot` partition unused by
Debian; Debian can keep `/boot` inside its new unencrypted root LV. Reuse the
existing EFI system partition at `/boot/efi` without formatting, with a separate
Debian bootloader directory/entry. Back up EFI contents and record `efibootmgr -v`
before installing; bootloader changes still need an Ubuntu recovery path.

Initial sizes below are a starting point, not fixed requirements.

| Mount | Initial GiB | Purpose |
|---|---:|---|
| `/` | 64 | Debian, packages, admin homes, `/srv/the-loft` checkout |
| `/var` | 160 | Docker/containerd runtime storage, images, volumes and logs |
| `/opt` | 128 | Existing application database/configuration paths, Plex metadata |
| `/scratch` | 64 | Disposable Plex transcoding and temporary processing |
| swap | 8 provisional | Revisit after checking RAM and actual workload |
| Existing Ubuntu root | 100 | Retain unchanged for rollback |
| VG free space | approximately 404 | Grow volumes after measuring demand |

Separating `/var` and `/opt` limits the impact of image/cache growth on root and
application data. It does not protect against failure of the single SSD.
Inventory actual Docker data-root and containerd paths before assigning storage.
Named Docker volumes can contain important state and must be backed up too.
Keep application subdirectories rather than one partition per service.

Mount the existing XFS array at `/mammoth` by filesystem UUID. Do not reformat
the array as part of the OS change. Configure required mounts and startup checks
so Docker cannot start workloads against empty directories on root if a volume
is absent. Test missing-array boot behavior before production use.

## Media and temporary files

- Keep completed torrents/seeding data and libraries on the same XFS filesystem
  under `/mammoth/downloads` and `/mammoth/library`.
- For downloaders and *arr importers, use a consistent shared parent mapping
  `/mammoth:/data`, with `/data/downloads` and `/data/library` paths. Review
  permissions because that mapping exposes more directories to each container.
- Preserve Plex's current library paths inside its container initially to avoid
  an unnecessary library move/rescan during the OS cutover.
- Keep sidecar subtitles alongside media; Bazarr database/config stays in `/opt`.
- Torrent payloads belong on the array; Transmission resume/config state stays
  in `/opt/transmission`. Optional SSD incomplete-download staging is a separate
  decision: moving across filesystems requires copying and needs capacity bounds.
- Put disposable transcode data on `/scratch`, with limits and monitoring.
- Migrate importer paths in a separate stage after the OS restore. Verify a real
  import and matching inode/link counts from the host. Existing duplicate copies
  do not automatically become hardlinks when mounts change.
- Review the ratio-based torrent deletion job: it currently does not verify
  import completion. Correct that before relying on it in the revised layout.

See [Stellarr](../docs/services/stellarr.md) and the
[Servarr Docker guide](https://github.com/Servarr/Wiki/blob/master/docker-guide.md).

## Migration stages and acceptance criteria

1. Inventory Ubuntu version, RAM, filesystem UUIDs, disk/controller health,
   Compose versions/profiles, live image digests, container mounts and volumes,
   UID/GID ownership, `/etc` host configuration and all timers/cron jobs.
2. Back up application state consistently, per service, plus `.env` secrets,
   named volumes, n8n encryption key, Caddy state, Plex identity and relevant host
   keys/configuration. Record excluded bulk media explicitly. Keep a verified
   copy of irreplaceable data separate from this host/array. Test restoring state.
3. Install Debian into newly created LVs on the existing SSD, preserving Ubuntu
   and its `/boot` as described above. Back up LVM metadata, partition layout and
   EFI contents externally alongside application backups. Disconnect the RAID
   during installation after stopping its users and cleanly unmounting it.
   Verify Debian and Ubuntu can both boot before committing to cutover. They
   cannot run simultaneously on this machine; plan reboots and service downtime.
   Restore application data into Debian's own `/opt` and runtime volumes; do not
   have both OS installations use the same writable database directories.
4. Verify Debian NICs, NVMe, USB RAID stability and Intel `/dev/dri` support.
   Do not run the normal setup script until mounts and restored state are ready:
   it starts services automatically. Prepare a staged provisioning procedure.
5. Stop production writers, take final consistent backups, restore ownership and
   state, then bring services up at the recorded versions. Use temporary identity
   while testing; only one machine may own the production IP at cutover.
6. Verify DNS/TLS/tunnel, VPN egress, downloads/imports, Plex library identity and
   hardware transcode, Music Assistant groups, databases, metrics and backups.
   Perform a reboot and verify mount ordering and startup behavior.
7. Migrate media-container paths separately; verify hardlinks, seeding, subtitles
   and cleanup behavior. Upgrade service versions only in later maintenance work.
8. Retain the Ubuntu root/boot volumes and backups until acceptance. If production
   data changes after cutover, rollback needs consistent current data or explicit acceptance of lost
   writes; booting Ubuntu alone is not a complete rollback.

## Reliability follow-up

Add disk/inode alerts for each filesystem, bounded journal/container logs and
build-cache retention, actual SMART/controller monitoring, mount-failure alerts,
backup freshness checks and scheduled restore drills. Check UPS coverage and
shutdown behavior for both server and array. RAID is availability, not backup.

## Decisions still needed

- Acceptable downtime and confirmation the reported VG free space is unchanged.
- D5-300 management access for member health and rebuild status.
- Backup destination independent of the array and which bulk media is irreplaceable.
- RAM, encryption/unattended boot preference and any requirement for SSD torrent
  staging rather than array downloads.

The preserved Ubuntu installation shares the same SSD and EFI partition as
Debian, so it is a rollback convenience, not an independent backup. An independent
backup destination remains undecided. D5-300 RAID management/SMART access must be
verified separately from Linux filesystem access; keep its existing RAID mode.

## Resume checklist

When the operator resumes this project, collect on space-needle:

```bash
cat /etc/os-release
free -h
df -hT / /opt /mammoth
sudo pvs
sudo vgs
sudo lvs -a -o lv_name,vg_name,lv_size,devices
lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS,MODEL,TRAN
sudo efibootmgr -v
sudo docker system df
sudo smartctl -a /dev/nvme0n1
sudo smartctl --scan-open
```

If smartctl remains unavailable, install `smartmontools` when resuming. Obtain
D5-300 array/member health through a verified supported management method; do
not interpret an empty `/proc/mdstat` or a successful XFS mount as proof of RAID
health. Review kernel storage errors as part of the same assessment.

Confirm the backup destination, restore procedure and downtime window next.
Only then convert this proposal into exact volume creation, installer,
restoration, boot recovery and acceptance steps. Preserve existing service
versions and use the [upgrade/backup guide](../docs/operations/upgrades.md) for
service-specific state and rollback limitations.
