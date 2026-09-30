#!/usr/bin/env bash
# Start the gateway in Termux in the background over SSH. Device must be connected via adb.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TERMUX_SSH_PASS
[ -r "$SCRIPT_DIR/.termux-ssh-pass" ] && TERMUX_SSH_PASS="$(cat "$SCRIPT_DIR/.termux-ssh-pass")"
export TERMUX_SSH_USER
TERMUX_SSH_USER="${TERMUX_SSH_USER:?Set TERMUX_SSH_USER (run whoami in Termux)}"

echo "Starting gateway in Termux (background)..."
"$SCRIPT_DIR/termux-ssh.sh" "nohup ~/run-gateway.sh > ~/gateway.log 2>&1 &"
echo "Gateway starting. Test with: ./scripts/start-gateway-and-test.sh"
