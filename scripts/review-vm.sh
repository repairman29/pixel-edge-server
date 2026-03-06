#!/usr/bin/env bash
# Review Pixel Debian VM state via SSH. Run from Mac.
# Usage: ./scripts/review-vm.sh
# Requires: Pixel connected via USB (adb forward) OR reachable via Tailscale.
# If using USB: run "adb forward tcp:8022 tcp:8022" first.
# Uses one SSH command per section to avoid "Connection closed" with heredocs.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

echo "=== Reviewing VM (${VM_HOST}:${VM_PORT}) ==="
echo ""

run() { vm_ssh "$@"; }

echo "--- System ---"
run "uname -a" || true
echo ""

echo "--- Docker ---"
run "docker --version 2>/dev/null; systemctl is-active docker 2>/dev/null" || true
echo ""

echo "--- Node / nvm ---"
run "export NVM_DIR=\$HOME/.nvm; [ -s \$NVM_DIR/nvm.sh ] && . \$NVM_DIR/nvm.sh; nvm use 22 2>/dev/null; node -v 2>/dev/null" || true
echo ""

echo "--- OpenClaw ---"
run "export NVM_DIR=\$HOME/.nvm; [ -s \$NVM_DIR/nvm.sh ] && . \$NVM_DIR/nvm.sh; nvm use 22 2>/dev/null; which openclaw 2>/dev/null; openclaw --version 2>/dev/null" || true
echo ""

echo "--- Tailscale ---"
run "tailscale ip -4 2>/dev/null" || true
echo ""

echo "--- Listening (8022, 18789) ---"
run "ss -tlnp 2>/dev/null | grep -E '8022|18789'" || true
echo ""

echo "--- Disk ---"
run "df -h /" || true
echo ""

echo "=== Review complete ==="
