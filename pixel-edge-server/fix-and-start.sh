#!/data/data/com.termux/files/usr/bin/bash
# Fix config and start gateway

echo "=== Fixing Clawdbot Config ==="
echo ""

# Kill any running gateway
pkill -9 -f "clawdbot gateway" 2>/dev/null
sleep 2

echo "Step 1: Creating clean config..."
mkdir -p ~/.clawdbot

# Clean config - ONLY valid keys
cat > ~/.clawdbot/clawdbot.json << 'EOF'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan"
  }
}
EOF

echo "  ✓ Clean config created"
echo ""

echo "Step 2: Creating required directories..."
mkdir -p ~/.clawdbot/agents/main/sessions
mkdir -p ~/tmp
echo "  ✓ Directories created"
echo ""

echo "Step 3: Running clawdbot doctor..."
cd ~/JARVIS
./node_modules/.bin/clawdbot doctor --fix
echo ""

echo "Step 4: Starting gateway..."
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp

echo "Starting on port 18789..."
echo ""
./node_modules/.bin/clawdbot gateway run &
PID=$!

echo "Gateway started with PID: $PID"
echo ""
echo "Waiting 5 seconds for startup..."
sleep 5

echo ""
echo "Testing connection..."
if ps | grep -q "$PID"; then
    echo "✓ Gateway process is running"
    echo ""
    echo "Test with:"
    echo "  curl http://127.0.0.1:18789/health"
    echo ""
    echo "=== Gateway is running! ==="
else
    echo "✗ Gateway failed to start"
fi
