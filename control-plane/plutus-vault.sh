#!/usr/bin/env bash
# plutus-vault.sh — unlock, lock or report Plutus's encrypted volume.
#
#   sudo control-plane/plutus-vault.sh unlock   # passphrase prompt, mount, dirs
#   sudo control-plane/plutus-vault.sh lock     # after `loft-ctl stop plutus`
#   control-plane/plutus-vault.sh status
#
# The volume is LUKS2 on an LVM logical volume on space-needle's NVMe, mounted
# at /plutus. Plutus's Compose binds only directories inside it and never
# creates them, so while the vault is locked Docker refuses to start Plutus
# instead of initialising an empty archive on the unencrypted disk. This script
# creates those directories only once /plutus is confirmed to be the vault.
#   docs/services/plutus.md
set -euo pipefail

: "${PLUTUS_DEVICE:=/dev/ubuntu-vg/plutus}"
: "${PLUTUS_MAPPER:=plutus}"
: "${PLUTUS_MAPPER_DEV:=/dev/mapper/${PLUTUS_MAPPER}}"
: "${PLUTUS_MOUNT:=/plutus}"
: "${PLUTUS_OWNER:=littledog:pack-member}"
: "${PLUTUS_REQUIRE_ROOT:=1}"

# Paperless runs as PLUTUS_OWNER (USERMAP_UID/GID); Postgres and Valkey chown
# their own directories on first start, so those are only created.
APP_DIRS=(data media consume export)
SERVICE_DIRS=(db redis)

die() { echo "plutus-vault: $*" >&2; exit 1; }

need_root() {
  [[ "$PLUTUS_REQUIRE_ROOT" != 1 || "$EUID" -eq 0 ]] || die "run with sudo"
}

is_open()    { cryptsetup status "$PLUTUS_MAPPER" > /dev/null 2>&1; }
mounted_at() { findmnt -n -o SOURCE --mountpoint "$PLUTUS_MOUNT" 2> /dev/null || true; }
is_mounted() { [[ "$(mounted_at)" == "$PLUTUS_MAPPER_DEV" ]]; }

unlock() {
  need_root
  [[ -e "$PLUTUS_DEVICE" ]] || die "${PLUTUS_DEVICE} not found; create the volume first (docs/services/plutus.md)"

  if ! is_open; then
    cryptsetup open "$PLUTUS_DEVICE" "$PLUTUS_MAPPER" || die "could not open ${PLUTUS_DEVICE}"
  fi

  if ! is_mounted; then
    local other
    other="$(mounted_at)"
    [[ -z "$other" ]] || die "${PLUTUS_MOUNT} has ${other} mounted, not the vault"
    mkdir -p "$PLUTUS_MOUNT"
    mount "$PLUTUS_MAPPER_DEV" "$PLUTUS_MOUNT" || die "could not mount ${PLUTUS_MAPPER_DEV}"
  fi
  # Never create Plutus's directories anywhere but the unlocked vault.
  is_mounted || die "${PLUTUS_MOUNT} is not the vault after mounting"

  local d
  for d in "${APP_DIRS[@]}"; do
    install -d -o "${PLUTUS_OWNER%%:*}" -g "${PLUTUS_OWNER##*:}" -m 750 "${PLUTUS_MOUNT}/${d}"
  done
  for d in "${SERVICE_DIRS[@]}"; do
    [[ -d "${PLUTUS_MOUNT}/${d}" ]] || install -d -m 700 "${PLUTUS_MOUNT}/${d}"
  done
  echo "Vault unlocked at ${PLUTUS_MOUNT}. Start Plutus: loft-ctl start plutus"
}

lock() {
  need_root
  if [[ -n "$(docker ps -q --filter label=com.docker.compose.project=plutus)" ]]; then
    die "Plutus is running; stop it first: loft-ctl stop plutus"
  fi
  if is_mounted; then
    umount "$PLUTUS_MOUNT" || die "could not unmount ${PLUTUS_MOUNT}"
  fi
  if is_open; then
    cryptsetup close "$PLUTUS_MAPPER" || die "could not close ${PLUTUS_MAPPER}"
  fi
  echo "Vault locked."
}

status() {
  if is_mounted; then
    echo "unlocked: ${PLUTUS_MAPPER_DEV} on ${PLUTUS_MOUNT}"
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
  *) die "usage: plutus-vault.sh unlock|lock|status" ;;
esac
