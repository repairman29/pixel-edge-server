#!/bin/bash
# Quick gateway starter

echo "Starting OpenClaw Gateway..."
cd ~/JARVIS

# Kill existing gateway
pkill -f "clawdbot gateway" 2>/dev/null
sleep 2

# Start gateway
export BIND_LAN=1
export PORT=18789
export TMPDIR=~/tmp
mkdir -p $TMPDIR

nohup npx clawdbot gateway run --allow-unconfigured --port 18789 > ~/gateway.log 2>&1 &
echo $! > ~/gateway.pid

echo "Gateway starting on port 18789..."
echo "Check status: curl http://127.0.0.1:18789/health"
