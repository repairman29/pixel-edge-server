#!/data/data/com.termux/files/usr/bin/bash
# Proper gateway start for Android/Termux

echo "=== Starting Clawdbot Gateway on Android ==="
echo ""

# Kill old processes
pkill -9 -f "clawdbot gateway" 2>/dev/null
pkill -9 -f ":18789" 2>/dev/null
sleep 2

cd ~/JARVIS || { echo "ERROR: Cannot cd to ~/JARVIS"; exit 1; }

echo "Current directory: $(pwd)"
echo ""

# Fix config first (doctor already ran)
echo "Ensuring proper config..."
mkdir -p ~/.clawdbot/agents/main/sessions

cat > ~/.clawdbot/clawdbot.json << 'EOF'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan"
  }
}
EOF

echo "✓ Config ready"
echo ""

# Set environment
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp
mkdir -p $TMPDIR

echo "Starting gateway..."
echo ""
echo "=== GATEWAY OUTPUT ==="
echo ""

# Run gateway DIRECTLY (no service install)
# This works on Android - just run, don't install
./node_modules/.bin/clawdbot gateway run
