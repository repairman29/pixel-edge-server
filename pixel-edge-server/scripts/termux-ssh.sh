#!/usr/bin/env bash
# Run a command in Termux over SSH (device must have adb connected and Termux sshd on 8022).
# Set password in Termux: passwd
# Get username in Termux: whoami
# On Mac: export TERMUX_SSH_USER=u0_a123 TERMUX_SSH_PASS=yourpass
#   Or put password in scripts/.termux-ssh-pass (gitignored)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

TERMUX_SSH_USER="${TERMUX_SSH_USER:-}"
TERMUX_SSH_PASS="${TERMUX_SSH_PASS:-}"
if [ -z "$TERMUX_SSH_PASS" ] && [ -r "$SCRIPT_DIR/.termux-ssh-pass" ]; then
  TERMUX_SSH_PASS="$(cat "$SCRIPT_DIR/.termux-ssh-pass")"
fi

if [ -z "$TERMUX_SSH_USER" ]; then
  echo "Set TERMUX_SSH_USER (run 'whoami' in Termux to get it)." >&2
  exit 1
fi

adb forward tcp:8022 tcp:8022 2>/dev/null || true

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p 8022 "$TERMUX_SSH_USER@127.0.0.1")

if [ -n "$TERMUX_SSH_PASS" ]; then
  if command -v sshpass &>/dev/null; then
    export SSHPASS="$TERMUX_SSH_PASS"
    sshpass -e ssh "${SSH_OPTS[@]}" "$@"
  else
    echo "Install sshpass for non-interactive SSH (brew install sshpass), or run without TERMUX_SSH_PASS and enter password when prompted." >&2
    ssh "${SSH_OPTS[@]}" "$@"
  fi
else
  ssh "${SSH_OPTS[@]}" "$@"
fi
