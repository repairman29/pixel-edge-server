#!/usr/bin/env bash
# Run the pixel-agent-v2 build inside Termux over SSH. Takes 5–15 min. Device must be connected via adb.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TERMUX_SSH_PASS
[ -r "$SCRIPT_DIR/.termux-ssh-pass" ] && TERMUX_SSH_PASS="$(cat "$SCRIPT_DIR/.termux-ssh-pass")"
export TERMUX_SSH_USER
TERMUX_SSH_USER="${TERMUX_SSH_USER:?Set TERMUX_SSH_USER (run whoami in Termux)}"

echo "Forwarding SSH port and running build in Termux (5–15 min)..."
"$SCRIPT_DIR/termux-ssh.sh" "bash /sdcard/jarvis/build-in-termux.sh"
echo "Build finished. Start gateway with: ./scripts/start-gateway-via-ssh.sh"
