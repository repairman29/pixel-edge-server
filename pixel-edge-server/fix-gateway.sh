#!/data/data/com.termux/files/usr/bin/bash
# Proper gateway debug and start

echo "=== Gateway Debug & Start ==="
echo ""

# Kill any existing gateway processes
pkill -f "clawdbot gateway" 2>/dev/null
pkill -f "18789" 2>/dev/null
sleep 2

cd ~/JARVIS || { echo "ERROR: Cannot cd to ~/JARVIS"; exit 1; }

echo "Current directory: $(pwd)"
echo ""

# Check if clawdbot exists
if [ -f "node_modules/.bin/clawdbot" ]; then
    echo "✓ clawdbot found in node_modules/.bin"
    echo "Version: $(node_modules/.bin/clawdbot --version 2>&1)"
else
    echo "✗ clawdbot NOT found in node_modules/.bin"
    echo "Installing..."
    npm install
fi

echo ""
echo "Setting up environment..."
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp
mkdir -p $TMPDIR

echo ""
echo "Starting gateway with full output..."
echo "Command: ./node_modules/.bin/clawdbot gateway run --allow-unconfigured --port 18789"
echo ""

# Run in foreground to see errors
./node_modules/.bin/clawdbot gateway run --allow-unconfigured --port 18789 2>&1 | tee ~/gateway-live.log &

# Wait a moment
sleep 5

echo ""
echo "Checking if gateway process is running..."
if ps | grep -q "clawdbot"; then
    echo "✓ Gateway process found"
    ps | grep clawdbot
    
    echo ""
    echo "Testing port 18789..."
    sleep 2
    
    # Try to connect
    (echo "GET /health HTTP/1.1"; echo "Host: 127.0.0.1:18789"; echo ""; sleep 1) | nc 127.0.0.1 18789 2>&1 || echo "Connection failed"
    
    echo ""
    echo "Last 20 lines of log:"
    tail -20 ~/gateway-live.log 2>&1 || echo "Log file not created yet"
    
    echo ""
    echo "Gateway should now be running on port 18789"
    echo "Test with: curl http://127.0.0.1:18789/health"
else
    echo "✗ Gateway process NOT found - it crashed immediately"
    echo ""
    echo "Checking log for errors:"
    tail -30 ~/gateway-live.log 2>&1 || echo "No log file"
    
    echo ""
    echo "Trying alternative start method..."
    echo "Running: npx clawdbot gateway run --allow-unconfigured --port 18789"
    npx clawdbot gateway run --allow-unconfigured --port 18789 2>&1 | tee ~/gateway-npx.log &
    
    sleep 5
    
    if ps | grep -q "clawdbot"; then
        echo "✓ Gateway started via npx"
    else
        echo "✗ Also failed via npx"
        echo "Error log:"
        tail -20 ~/gateway-npx.log 2>&1
    fi
fi

echo ""
echo "=== Debug Complete ==="
