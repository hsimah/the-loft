#!/usr/bin/env bash
# mercurius-vault.sh — unlock, lock or report Mercurius's encrypted volume.
#
#   sudo control-plane/mercurius-vault.sh unlock   # passphrase prompt, mount, dirs
#   sudo control-plane/mercurius-vault.sh lock     # after `loft-ctl stop mercurius`
#   control-plane/mercurius-vault.sh status
#
# The volume is LUKS2 on an LVM logical volume on space-needle's NVMe, mounted
# at /mercurius. Mercurius's Compose binds only directories inside it and
# never creates them, so while the vault is locked Docker refuses to start the
# group instead of initialising an empty archive or wiki on the unencrypted
# disk. This script creates those directories only once /mercurius is
# confirmed to be the vault.
#   docs/services/mercurius.md
set -euo pipefail

: "${MERCURIUS_DEVICE:=/dev/ubuntu-vg/mercurius}"
: "${MERCURIUS_MAPPER:=mercurius}"
: "${MERCURIUS_MAPPER_DEV:=/dev/mapper/${MERCURIUS_MAPPER}}"
: "${MERCURIUS_MOUNT:=/mercurius}"
: "${MERCURIUS_OWNER:=littledog:pack-member}"
: "${MERCURIUS_REQUIRE_ROOT:=1}"

# Paperless, paperless-gpt (gpt/) and SilverBullet (silverbullet/, as the
# folder's owner) run as MERCURIUS_OWNER (USERMAP_UID/GID and PUID/PGID;
# parents are listed before children). Postgres and Valkey are only given a
# directory: Postgres 18 chowns just its PGDATA subdirectory (18/docker, mode
# 700), so the parent must stay traversable (755).
APP_DIRS=(data media consume export gpt gpt/config gpt/db gpt/prompts silverbullet)
SERVICE_DIRS=(db redis)

die() { echo "mercurius-vault: $*" >&2; exit 1; }

need_root() {
  [[ "$MERCURIUS_REQUIRE_ROOT" != 1 || "$EUID" -eq 0 ]] || die "run with sudo"
}

is_open()    { cryptsetup status "$MERCURIUS_MAPPER" > /dev/null 2>&1; }
mounted_at() { findmnt -n -o SOURCE --mountpoint "$MERCURIUS_MOUNT" 2> /dev/null || true; }
is_mounted() { [[ "$(mounted_at)" == "$MERCURIUS_MAPPER_DEV" ]]; }

unlock() {
  need_root
  [[ -e "$MERCURIUS_DEVICE" ]] || die "${MERCURIUS_DEVICE} not found; create the volume first (docs/services/mercurius.md)"

  if ! is_open; then
    cryptsetup open "$MERCURIUS_DEVICE" "$MERCURIUS_MAPPER" || die "could not open ${MERCURIUS_DEVICE}"
  fi

  if ! is_mounted; then
    local other
    other="$(mounted_at)"
    [[ -z "$other" ]] || die "${MERCURIUS_MOUNT} has ${other} mounted, not the vault"
    mkdir -p "$MERCURIUS_MOUNT"
    mount "$MERCURIUS_MAPPER_DEV" "$MERCURIUS_MOUNT" || die "could not mount ${MERCURIUS_MAPPER_DEV}"
  fi
  # Never create Mercurius's directories anywhere but the unlocked vault.
  is_mounted || die "${MERCURIUS_MOUNT} is not the vault after mounting"

  local d
  for d in "${APP_DIRS[@]}"; do
    install -d -o "${MERCURIUS_OWNER%%:*}" -g "${MERCURIUS_OWNER##*:}" -m 750 "${MERCURIUS_MOUNT}/${d}"
  done
  for d in "${SERVICE_DIRS[@]}"; do
    [[ -d "${MERCURIUS_MOUNT}/${d}" ]] || install -d -m 755 "${MERCURIUS_MOUNT}/${d}"
  done
  echo "Vault unlocked at ${MERCURIUS_MOUNT}. Start the group: loft-ctl start mercurius"
}

lock() {
  need_root
  if [[ -n "$(docker ps -q --filter label=com.docker.compose.project=mercurius)" ]]; then
    die "Mercurius is running; stop it first: loft-ctl stop mercurius"
  fi
  if is_mounted; then
    umount "$MERCURIUS_MOUNT" || die "could not unmount ${MERCURIUS_MOUNT}"
  fi
  if is_open; then
    cryptsetup close "$MERCURIUS_MAPPER" || die "could not close ${MERCURIUS_MAPPER}"
  fi
  echo "Vault locked."
}

status() {
  if is_mounted; then
    echo "unlocked: ${MERCURIUS_MAPPER_DEV} on ${MERCURIUS_MOUNT}"
  elif is_open; then
    echo "open but not mounted: run unlock again"
  else
    echo "locked"
  fi
}

case "${1:-}" in
  unlock) unlock ;;
  lock)   lock ;;
  status) status ;;
  *) die "usage: mercurius-vault.sh unlock|lock|status" ;;
esac
