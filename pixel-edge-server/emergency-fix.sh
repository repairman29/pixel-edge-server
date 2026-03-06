#!/data/data/com.termux/files/usr/bin/bash
# Emergency gateway fix

echo "Killing old processes..."
pkill -9 -f "clawdbot" 2>/dev/null
sleep 2

cd ~/JARVIS
echo "In directory: $(pwd)"

# Check node_modules
if [ ! -d "node_modules/@anthropic-ai/clawdbot" ] && [ ! -d "node_modules/clawdbot" ]; then
    echo "ERROR: clawdbot not installed"
    echo "Run: cd ~/JARVIS && npm install"
    exit 1
fi

# Check for binary
if [ -f "node_modules/.bin/clawdbot" ]; then
    echo "Found clawdbot binary"
    CLAWDBOT="./node_modules/.bin/clawdbot"
elif [ -f "node_modules/@anthropic-ai/clawdbot/bin/clawdbot" ]; then
    echo "Found clawdbot in @anthropic-ai"
    CLAWDBOT="node_modules/@anthropic-ai/clawdbot/bin/clawdbot"
else
    echo "ERROR: Cannot find clawdbot binary"
    find node_modules -name "clawdbot" -type f 2>/dev/null | head -5
    exit 1
fi

echo ""
echo "Starting gateway on port 18789..."
echo "Using: $CLAWDBOT"
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp
mkdir -p $TMPDIR

# Start with output
echo ""
$CLAWDBOT gateway run --allow-unconfigured --port 18789 2>&1 &
PID=$!
echo "Started with PID: $PID"

sleep 3
echo ""
echo "Checking if process is alive..."
if ps | grep -q "$PID"; then
    echo "✓ Process is running"
    echo "Testing port..."
    sleep 2
    (echo -e "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"; sleep 1) | nc 127.0.0.1 18789 2>&1 | head -5 || echo "Port not responding yet"
else
    echo "✗ Process died immediately"
    echo "Try running manually to see error:"
    echo "cd ~/JARVIS && $CLAWDBOT gateway run --allow-unconfigured --port 18789"
fi
