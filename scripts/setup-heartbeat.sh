#!/usr/bin/env bash
# Create HEARTBEAT.md and a cron job so OpenClaw can run proactive checks on a schedule.
# Run from your Mac. Usage: ./scripts/setup-heartbeat.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"

echo "=== Setting up OpenClaw Heartbeat on ${TARGET} ==="

ssh $SSH_OPTS "$TARGET" bash -s << 'REMOTE'
set -e
mkdir -p ~/openclaw-heartbeat

# Default HEARTBEAT.md: checklist the agent can run on a schedule
cat > ~/openclaw-heartbeat/HEARTBEAT.md << 'HEART'
# Heartbeat checklist

Run these checks. If nothing needs action, respond with HEARTBEAT_OK.

1. Check thermal: run ~/bin/thermal-check.sh; if /tmp/thermal-check.log has recent entries, note them.
2. Check disk: df -h /
3. If all normal, reply HEARTBEAT_OK only.
HEART

# Cron: every 30 minutes, try to trigger the agent (OpenClaw may poll this file or we curl the gateway)
# OpenClaw heartbeat is often configured in the app; this cron ensures the file exists and can run a ping.
(crontab -l 2>/dev/null | grep -v openclaw-heartbeat; echo "*/30 * * * * [ -f ~/openclaw-heartbeat/HEARTBEAT.md ] && date >> ~/openclaw-heartbeat/heartbeat.log 2>/dev/null") | crontab - 2>/dev/null || true

echo "Created ~/openclaw-heartbeat/HEARTBEAT.md and heartbeat log cron."
echo "Configure OpenClaw to use HEARTBEAT.md (see OpenClaw docs for heartbeat/scheduled tasks)."
REMOTE

echo ""
echo "Heartbeat file and cron are set. Point OpenClaw's heartbeat/scheduler at ~/openclaw-heartbeat/HEARTBEAT.md if supported."
echo "Log: ssh -p 8022 $TARGET 'tail ~/openclaw-heartbeat/heartbeat.log'"