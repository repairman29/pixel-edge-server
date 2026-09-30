#!/data/data/com.termux/files/usr/bin/bash
# Start Clawdbot Gateway with MiniCPM4

echo "=== Starting Clawdbot Gateway ==="
echo ""

# Kill any existing processes
pkill -9 -f clawdbot 2>/dev/null
pkill -9 -f node 2>/dev/null
sleep 2

# Set TMPDIR to avoid /tmp permission issues
export TMPDIR=~/tmp
export TEMP=~/tmp
export TMP=~/tmp
mkdir -p ~/tmp

echo "TMPDIR set to: $TMPDIR"
echo ""

# Ensure config has miniCPM4
cd ~/JARVIS
~/config-minicpm4-pixel.sh

echo "Config updated to miniCPM4"
echo ""

# Start gateway
echo "Starting gateway..."
./node_modules/.bin/clawdbot gateway run --allow-unconfigured --port 18789 --bind lan 2>&1 | tee ~/clawdbot.log
