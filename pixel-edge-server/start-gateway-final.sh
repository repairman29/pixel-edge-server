#!/data/data/com.termux/files/usr/bin/bash
# FINAL Gateway Startup for Android/Termux
# This script properly configures and starts the Clawdbot gateway

echo "=========================================="
echo "  Clawdbot Gateway - Android/Termux"
echo "=========================================="
echo ""

# Configuration
GATEWAY_PORT=18790
JARVIS_DIR="$HOME/JARVIS"
CONFIG_DIR="$HOME/.clawdbot"

echo "Step 1: Cleanup old processes..."
pkill -9 -f "clawdbot gateway" 2>/dev/null
pkill -9 -f ":$GATEWAY_PORT" 2>/dev/null
sleep 2
echo "  ✓ Cleanup complete"
echo ""

# Check if JARVIS exists
if [ ! -d "$JARVIS_DIR" ]; then
    echo "ERROR: JARVIS directory not found at $JARVIS_DIR"
    exit 1
fi

cd "$JARVIS_DIR"
echo "Step 2: Setting up directories..."
mkdir -p "$CONFIG_DIR/agents/main/sessions"
mkdir -p ~/tmp
echo "  ✓ Directories created"
echo ""

echo "Step 3: Creating proper config..."
cat > "$CONFIG_DIR/clawdbot.json" << 'EOF'
{
  "gateway": {
    "mode": "local",
    "port": 18790,
    "bind": "lan"
  }
}
EOF
echo "  ✓ Config created at $CONFIG_DIR/clawdbot.json"
echo ""

echo "Step 4: Setting environment..."
export PORT=$GATEWAY_PORT
export BIND_LAN=1
export TMPDIR=~/tmp
echo "  ✓ Environment set"
echo ""

echo "Step 5: Starting gateway..."
echo "  Command: ./node_modules/.bin/clawdbot gateway run"
echo ""
echo "=========================================="
echo "  Gateway is starting..."
echo "  Port: $GATEWAY_PORT"
echo "=========================================="
echo ""

# Start gateway - this will block and show output
./node_modules/.bin/clawdbot gateway run
