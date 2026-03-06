#!/data/data/com.termux/files/usr/bin/bash
# FINAL - Start gateway with proper temp directory

echo "=== Starting Clawdbot Gateway ==="
echo ""

# Kill old processes
pkill -9 -f "clawdbot gateway" 2>/dev/null
sleep 2

echo "Setting up environment..."

# CRITICAL: Use home directory for temp, not /tmp
export TMPDIR=~/tmp
mkdir -p $TMPDIR

echo "  TMPDIR set to: $TMPDIR"
echo ""

echo "Starting gateway..."
cd ~/JARVIS

# Start gateway with output visible
./node_modules/.bin/clawdbot gateway run 2>&1 | tee ~/gateway-output.log &

PID=$!
echo ""
echo "Gateway PID: $PID"
echo ""
echo "Waiting 5 seconds..."
sleep 5

echo ""
echo "Checking status..."
if ps | grep -q "$PID"; then
    echo "✓ Gateway is running!"
    echo ""
    echo "Test with:"
    echo "  curl http://127.0.0.1:18789/health"
    echo ""
    echo "Or check logs:"
    echo "  tail -f ~/gateway-output.log"
else
    echo "✗ Gateway stopped"
    echo "Check error:"
    tail -20 ~/gateway-output.log
fi

echo ""
echo "=== Done ==="
