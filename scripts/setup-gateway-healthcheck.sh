#!/usr/bin/env bash
# Deploy gateway health-check script and cron to the Pixel VM.
# Every 5 minutes: if the gateway is unreachable, restart it.
# Run from your Mac. Usage: ./scripts/setup-gateway-healthcheck.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
SCP_OPTS="-P 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"
SCRIPT_NAME="gateway-healthcheck.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Deploying gateway health-check to ${TARGET} ==="

# Copy script to VM
scp $SCP_OPTS "$DIR/gateway-healthcheck.sh" "$TARGET:~/bin/${SCRIPT_NAME}"

# Install systemd user timer (every 5 min) — VM may not have cron
ssh $SSH_OPTS "$TARGET" bash -s << 'REMOTE'
set -e
mkdir -p ~/bin ~/openclaw-heartbeat ~/.config/systemd/user
chmod +x ~/bin/gateway-healthcheck.sh

# Service: run the healthcheck script
cat > ~/.config/systemd/user/gateway-healthcheck.service << 'SVC'
[Unit]
Description=OpenClaw gateway health-check and restart if unhealthy

[Service]
Type=oneshot
ExecStart=%h/bin/gateway-healthcheck.sh
SVC

# Timer: every 5 minutes
cat > ~/.config/systemd/user/gateway-healthcheck.timer << 'TMR'
[Unit]
Description=Run gateway health-check every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
TMR

systemctl --user daemon-reload
systemctl --user enable gateway-healthcheck.timer
systemctl --user start gateway-healthcheck.timer
systemctl --user list-timers --no-pager gateway-healthcheck.timer || true
echo "Timer installed: every 5 minutes"
REMOTE

echo ""
echo "Gateway health-check is installed and runs every 5 minutes (systemd timer)."
echo "Log: ssh -p 8022 $TARGET 'tail ~/openclaw-heartbeat/gateway-healthcheck.log'"
echo "Manual run: ssh -p 8022 $TARGET '~/bin/gateway-healthcheck.sh'"
