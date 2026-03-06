#!/usr/bin/env bash
# Fix Pixel VM (nvm, OpenClaw, gateway) and run review. Run from your Mac.
# Usage: ./scripts/fix-vm-and-review.sh [droid@127.0.0.1 | droid@100.78.73.64]
# Default: Tailscale (droid@100.78.73.64). For USB, run "adb forward tcp:8022 tcp:8022" first and pass droid@127.0.0.1.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Fix VM and review"

# If using USB, ensure adb forward is set
if [[ "$VM_HOST" == *"127.0.0.1"* ]]; then
  if command -v adb &>/dev/null; then
    echo "Setting up ADB port forward..."
    adb forward tcp:8022 tcp:8022 2>/dev/null || true
  fi
fi

# Step 1: Ensure we can connect. If not, set up SSH key.
echo "Checking SSH connection..."
if ! ssh -p "${VM_PORT}" -o ConnectTimeout=15 -o BatchMode=yes "$VM_HOST" "echo ok" 2>/dev/null; then
  echo "Key-based login not set up. You'll be asked for the VM password once."
  echo "Paste the password for user 'droid' on the Pixel VM:"
  ssh-copy-id $SSH_OPTS "$VM_HOST" || { echo "ssh-copy-id failed. Install OpenSSH on the Mac and try again."; exit 1; }
  echo "Key installed. Continuing..."
else
  echo "SSH key OK."
fi
echo ""

# Step 2: Ensure nvm is in .bashrc
echo "--- Ensuring nvm in .bashrc ---"
ssh -p "${VM_PORT}" -o ConnectTimeout=15 "$VM_HOST" "grep -q 'NVM_DIR' ~/.bashrc 2>/dev/null || (echo 'export NVM_DIR=\"\$HOME/.nvm\"' >> ~/.bashrc; echo '[ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"' >> ~/.bashrc); echo done"
echo ""

# Step 3: Install OpenClaw if missing
echo "--- Installing OpenClaw (if needed) ---"
ssh -p "${VM_PORT}" -o ConnectTimeout=15 "$VM_HOST" "export NVM_DIR=\$HOME/.nvm; [ -s \$NVM_DIR/nvm.sh ] && \. \$NVM_DIR/nvm.sh; nvm use 22 2>/dev/null; which openclaw &>/dev/null || npm install -g openclaw@latest; which openclaw && openclaw --version"
echo ""

# Step 4: Start OpenClaw gateway in background if not already listening on 18789
echo "--- Starting OpenClaw gateway if needed ---"
ssh -p "${VM_PORT}" -o ConnectTimeout=15 "$VM_HOST" "export NVM_DIR=\$HOME/.nvm; [ -s \$NVM_DIR/nvm.sh ] && \. \$NVM_DIR/nvm.sh; nvm use 22 2>/dev/null; ss -tlnp 2>/dev/null | grep -q 18789 || (nohup openclaw gateway >> /tmp/openclaw.log 2>&1 &); sleep 2; ss -tlnp 2>/dev/null | grep 18789 || echo 'Port 18789 not yet listening (gateway may still be starting)'"
echo ""

# Step 5: Run review
echo "=== Running review ==="
VM_HOST="$VM_HOST" VM_PORT="$VM_PORT" "$SCRIPT_DIR/review-vm.sh"
echo ""
echo "Done. Mission Control: http://100.78.73.64:18789"
