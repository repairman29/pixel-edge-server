#!/data/data/com.termux/files/usr/bin/bash
# Start Jarvy (OpenClaw Discord Bot) on Pixel
# Port: 18790 (avoids conflict with Maclawd on MacBook)

set -e

echo "=== Starting Jarvy (OpenClaw Discord Bot) ==="
echo "Port: 18790"
echo "Config: ~/.config/openclaw/config.json"
echo ""

# Kill any existing instances
echo "[1/4] Stopping existing instances..."
pkill -9 -f "clawdbot" 2>/dev/null || true
pkill -9 -f "openclaw" 2>/dev/null || true
sleep 1

# Check if port is free
echo "[2/4] Checking port 18790..."
if netstat -tlnp 2>/dev/null | grep -q ":18790"; then
    echo "ERROR: Port 18790 is already in use!"
    echo "Run: netstat -tlnp | grep 18790"
    exit 1
fi
echo "✓ Port 18790 is available"

# Verify config exists
echo "[3/4] Verifying configuration..."
if [ ! -f "$HOME/.config/openclaw/config.json" ]; then
    echo "ERROR: Config not found at ~/.config/openclaw/config.json"
    exit 1
fi

# Check Discord is enabled
if ! grep -q '"discord"' "$HOME/.config/openclaw/config.json"; then
    echo "WARNING: Discord configuration not found in config"
fi

echo "✓ Configuration verified"

# Start gateway
echo "[4/4] Starting OpenClaw gateway..."
echo ""
cd "$HOME/openclaw"

# Create log directory if needed
mkdir -p "$HOME/tmp"

# Start in background with logging
nohup node dist/entry.js gateway --bind loopback --port 18790 > "$HOME/tmp/jarvy.log" 2>&1 &

PID=$!
echo "✓ Gateway started (PID: $PID)"
echo ""

# Wait a moment and check if it's still running
sleep 2

if ps | grep -q "$PID"; then
    echo "=== Jarvy is now running! ==="
    echo ""
    echo "Process: $PID"
    echo "Port: 18790"
    echo "Logs: tail -f ~/tmp/jarvy.log"
    echo ""
    echo "Discord bot should appear online shortly."
    echo "If not, check that you've authorized the bot:"
    echo "  https://discord.com/oauth2/authorize?client_id=1478435625266053333&permissions=8&scope=bot"
    echo ""
    echo "To stop: pkill -9 -f clawdbot"
else
    echo "ERROR: Gateway failed to start!"
    echo "Check logs: cat ~/tmp/jarvy.log"
    exit 1
fi
