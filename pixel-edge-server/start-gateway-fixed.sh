#!/data/data/com.termux/files/usr/bin/bash
# Fix and start gateway properly

echo "=== Starting Gateway with Proper Config ==="
echo ""

# Kill old processes
pkill -9 -f "clawdbot gateway" 2>/dev/null
pkill -9 -f "18789" 2>/dev/null
sleep 2

cd ~/JARVIS

# Ensure config allows unconfigured mode
mkdir -p ~/.clawdbot
if [ -f ~/.clawdbot/clawdbot.json ]; then
    echo "Backing up existing config..."
    cp ~/.clawdbot/clawdbot.json ~/.clawdbot/clawdbot.json.bak.$(date +%s)
fi

# Create minimal config that allows gateway to start
cat > ~/.clawdbot/clawdbot.json << 'EOF'
{
  "version": "1.0.0",
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan",
    "allowUnconfigured": true
  }
}
EOF

echo "✓ Config created"
echo ""

# Set environment
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp
mkdir -p $TMPDIR

echo "Starting gateway..."
echo "Command: ./node_modules/.bin/clawdbot gateway run"
echo ""

# Start gateway (config should handle --allow-unconfigured)
./node_modules/.bin/clawdbot gateway run 2>&1 &
PID=$!

echo "Started with PID: $PID"
echo ""
echo "Waiting 5 seconds for startup..."
sleep 5

echo ""
echo "Checking if gateway is running..."
if ps | grep -q "$PID"; then
    echo "✓ Gateway process is alive (PID: $PID)"
    
    echo ""
    echo "Testing port 18789..."
    sleep 2
    
    # Try HTTP request
    RESPONSE=$( (echo -e "GET /health HTTP/1.1\r\nHost: 127.0.0.1:18789\r\n\r\n"; sleep 1) | nc 127.0.0.1 18789 2>&1 )
    
    if echo "$RESPONSE" | grep -q "200\|OK\|healthy"; then
        echo "✓ Gateway is responding!"
        echo "Response: $RESPONSE" | head -3
    else
        echo "⚠ Port check:"
        echo "$RESPONSE" | head -5
    fi
else
    echo "✗ Gateway failed to start"
    echo "Checking recent logs..."
    ls -lt ~/ | head -5
fi

echo ""
echo "=== Gateway startup complete ==="
echo ""
echo "If running, test with:"
echo "  curl http://127.0.0.1:18789/health"
