#!/data/data/com.termux/files/usr/bin/bash
# Debug gateway startup

echo "=== Gateway Debug Script ==="
echo "Date: $(date)"
echo ""

cd ~/JARVIS || { echo "ERROR: ~/JARVIS not found"; exit 1; }

echo "Directory: $(pwd)"
echo "Node version: $(node --version 2>&1)"
echo "NPM version: $(npm --version 2>&1)"
echo ""

echo "Checking if clawdbot is installed..."
ls -la node_modules/.bin/clawdbot 2>&1 || echo "clawdbot not found in node_modules/.bin"

echo ""
echo "Attempting to start gateway..."
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp
mkdir -p $TMPDIR

# Try running with npx
echo "Running: npx clawdbot gateway run --allow-unconfigured --port 18789"
npx clawdbot gateway run --allow-unconfigured --port 18789 2>&1 &
PID=$!
echo "PID: $PID"
sleep 5

# Check if it's running
if ps | grep -q "$PID"; then
    echo "Gateway process is running (PID: $PID)"
    echo "Testing port 18789..."
    sleep 2
    curl -s http://127.0.0.1:18789/health 2>&1 || echo "Port not responding"
else
    echo "Gateway process exited immediately"
    echo "Waiting to see if log file has errors..."
    sleep 3
    tail -30 ~/gateway.log 2>&1 || echo "No log file"
fi

echo ""
echo "=== End of debug script ==="
