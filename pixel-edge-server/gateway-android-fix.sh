#!/data/data/com.termux/files/usr/bin/bash
# FIX: Start Clawdbot Gateway on Android with proper TMPDIR

echo "=========================================="
echo "  Clawdbot Gateway - Android Fix"
echo "=========================================="
echo ""

# Step 1: Setup temp directory
echo "Step 1: Setting up temp directory..."
export TMPDIR="$HOME/tmp"
export TEMP="$TMPDIR"
export TMP="$TMPDIR"

mkdir -p "$TMPDIR"
mkdir -p "$TMPDIR/clawdbot"

echo "  TMPDIR=$TMPDIR"
echo "  Created: $TMPDIR/clawdbot"
echo ""

# Step 2: Kill any existing gateway
echo "Step 2: Stopping any existing gateway..."
pkill -9 -f "clawdbot gateway" 2>/dev/null
sleep 2
echo "  ✓ Old processes killed"
echo ""

# Step 3: Setup config
echo "Step 3: Setting up config..."
cd "$HOME/JARVIS" || { echo "ERROR: Cannot find ~/JARVIS"; exit 1; }

mkdir -p "$HOME/.clawdbot/agents/main/sessions"

# Clean config
cat > "$HOME/.clawdbot/clawdbot.json" << 'EOF'
{
  "gateway": {
    "mode": "local",
    "port": 18790,
    "bind": "lan"
  }
}
EOF
echo "  ✓ Config created"
echo ""

# Step 4: Start gateway
echo "Step 4: Starting gateway on port 18790..."
echo ""
echo "Running: ./node_modules/.bin/clawdbot gateway run"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start gateway - this will block and show output
exec ./node_modules/.bin/clawdbot gateway run
