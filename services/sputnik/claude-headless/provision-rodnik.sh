#!/usr/bin/env bash
# Run as root on space-needle from inside the claude-headless directory.
# Usage: sudo ./provision-rodnik.sh <path-to-n8n-public-key>
set -euo pipefail

readonly runner_user="rodnik"
readonly n8n_public_key_path="${1:?usage: provision-rodnik.sh <path-to-n8n-public-key>}"
readonly source_directory="$(cd "$(dirname "$0")" && pwd)"

if ! id "$runner_user" >/dev/null 2>&1; then
  useradd --system --create-home --shell /bin/bash "$runner_user"
fi

readonly runner_home="$(getent passwd "$runner_user" | cut -d: -f6)"
readonly runner_build_directory="$runner_home/claude-headless-build"
readonly runner_quadlet_directory="$runner_home/.config/containers/systemd"

grep --quiet "^$runner_user:" /etc/subuid || usermod --add-subuids 200000-265535 "$runner_user"
grep --quiet "^$runner_user:" /etc/subgid || usermod --add-subgids 200000-265535 "$runner_user"
loginctl enable-linger "$runner_user"

install --directory --owner="$runner_user" --group="$runner_user" --mode=0700 \
  "$runner_home/.ssh" \
  "$runner_home/bin" \
  "$runner_home/workspaces" \
  "$runner_home/claude-state" \
  "$runner_build_directory" \
  "$runner_quadlet_directory"

install --owner="$runner_user" --group="$runner_user" --mode=0755 \
  "$source_directory/claude-headless-ssh-command" "$runner_home/bin/claude-headless-ssh-command"

install --owner="$runner_user" --group="$runner_user" --mode=0644 \
  "$source_directory/Containerfile.claude-headless" \
  "$source_directory/run-claude-in-container" \
  "$source_directory/Containerfile.claude-egress-proxy" \
  "$source_directory/tinyproxy.conf" \
  "$source_directory/tinyproxy-allowed-hosts" \
  "$runner_build_directory/"

install --owner="$runner_user" --group="$runner_user" --mode=0644 \
  "$source_directory"/quadlets/* "$runner_quadlet_directory/"

readonly n8n_public_key="$(<"$n8n_public_key_path")"
printf 'restrict,command="%s/bin/claude-headless-ssh-command" %s\n' "$runner_home" "$n8n_public_key" \
  > "$runner_home/.ssh/authorized_keys"
chown "$runner_user:$runner_user" "$runner_home/.ssh/authorized_keys"
chmod 0600 "$runner_home/.ssh/authorized_keys"

runuser --user "$runner_user" -- bash -euo pipefail -c '
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  cd "$HOME/claude-headless-build"
  podman build --file Containerfile.claude-headless --tag localhost/claude-headless:latest .
  podman build --file Containerfile.claude-egress-proxy --tag localhost/claude-egress-proxy:latest .
  systemctl --user daemon-reload
  systemctl --user start claude-egress-proxy.service
'

cat <<NEXT_STEPS
Provisioned $runner_user. Remaining manual steps:
  1. Store the subscription token as a Podman secret:
       sudo machinectl shell $runner_user@ /bin/bash -c 'read -rs token && printf %s "\$token" | podman secret create claude-code-oauth-token -'
  2. Give $runner_user a key for Forgejo: ssh-keygen -t ed25519 as $runner_user, add the public
     key to its Forgejo account, and add a "Host kennl" block to $runner_home/.ssh/config
     (HostName kennl.loft.hsimah.com, Port 2222, User git, IdentitiesOnly yes). The forced
     command clones and pushes through that alias; repositories are whatever the account can reach.
NEXT_STEPS
