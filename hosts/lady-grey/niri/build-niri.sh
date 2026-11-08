#!/usr/bin/env bash
# build-niri.sh — build Lady Grey's pinned niri release in a throwaway Debian
# container. Debian does not package niri. The container keeps the Rust
# toolchain and -dev packages off the host, and the binary links against the
# same trixie libraries the bootstrap installs, so any x86_64 Docker host can
# build it: space-needle in minutes, or Lady Grey itself (slowly) as fallback.
#
# Usage: build-niri.sh [out-dir]   (default: current directory)
# Reads NIRI_TAG and NIRI_COMMIT from hosts/lady-grey/host.conf and writes
# <out-dir>/niri-<tag>.tar.gz: niri, niri-session, niri.service and
# niri-shutdown.target.
set -euo pipefail

# shellcheck source=../host.conf
source "$(dirname "${BASH_SOURCE[0]}")/../host.conf"
mkdir -p "${1:-.}"
out="$(cd "${1:-.}" && pwd)"
# Same pinned base as services/howlr/Dockerfile.snapclient.
image="debian:trixie-20260918-slim"

docker run --rm -v "$out:/out" -e TAG="$NIRI_TAG" -e COMMIT="$NIRI_COMMIT" "$image" bash -euo pipefail -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    ca-certificates git cargo rustc gcc clang pkg-config \
    libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev libwayland-dev \
    libinput-dev libdbus-1-dev libsystemd-dev libseat-dev libpango1.0-dev \
    libdisplay-info-dev > /dev/null
  git clone -q --depth 1 --branch "$TAG" https://github.com/niri-wm/niri /src
  cd /src
  [[ "$(git rev-parse HEAD)" == "$COMMIT" ]] || { echo "niri $TAG is not $COMMIT" >&2; exit 1; }
  # No screencast: drops the PipeWire dependency a kiosk never uses.
  cargo build -q --release --locked --no-default-features --features dbus,systemd
  mkdir /stage
  install -s -m 755 target/release/niri /stage/
  install -m 755 resources/niri-session /stage/
  install -m 644 resources/niri.service resources/niri-shutdown.target /stage/
  tar -czf "/out/niri-$TAG.tar.gz" -C /stage .
'
echo "${out}/niri-${NIRI_TAG}.tar.gz"
