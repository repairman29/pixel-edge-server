#!/usr/bin/env bash
# Install OpenClaw gateway as a systemd user service so it survives reboots and restarts.
# Run from your Mac. Uses Tailscale by default.
# Usage: ./scripts/setup-openclaw-daemon.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"

echo "=== Setting up OpenClaw daemon on ${TARGET} ==="

# Create wrapper and systemd user service in the VM
ssh $SSH_OPTS "$TARGET" bash -s << 'REMOTE'
set -e
mkdir -p ~/bin ~/.config/systemd/user

# Wrapper: load nvm and run openclaw gateway (optionally on prime core with taskset)
cat > ~/bin/openclaw-gateway-start.sh << 'WRAP'
#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 22 2>/dev/null || true
# Optional: pin to prime core (Tensor G3). Remove the 'taskset -c 0' to use all cores.
exec taskset -c 0 openclaw gateway
WRAP
chmod +x ~/bin/openclaw-gateway-start.sh

# Systemd user service (MemoryMax limits OOM impact; RestartSec avoids tight crash loops)
cat > ~/.config/systemd/user/openclaw-gateway.service << 'SVC'
[Unit]
Description=OpenClaw gateway
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=%h/bin/openclaw-gateway-start.sh
Restart=always
RestartSec=15
MemoryMax=450M

[Install]
WantedBy=default.target
SVC

# Enable user lingering so the service runs without an active login
sudo loginctl enable-linger "$USER" 2>/dev/null || true

# Reload, enable, and start
systemctl --user daemon-reload
systemctl --user enable openclaw-gateway.service
systemctl --user restart openclaw-gateway.service
systemctl --user status openclaw-gateway.service --no-pager || true
REMOTE

echo ""
echo "OpenClaw gateway is installed as a user service and should be running."
echo "Mission Control: http://100.78.73.64:18789"
echo "To check: ssh -p 8022 $TARGET 'systemctl --user status openclaw-gateway'"
echo "To stop:  ssh -p 8022 $TARGET 'systemctl --user stop openclaw-gateway'"
echo "To start: ssh -p 8022 $TARGET 'systemctl --user start openclaw-gateway'"
