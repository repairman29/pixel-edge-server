#!/data/data/com.termux/files/usr/bin/bash
# Find and patch clawdbot tmpdir

echo "=== Patching Clawdbot Source ==="
echo ""

cd ~/JARVIS

# Find where /tmp is hardcoded
echo "Searching for hardcoded /tmp in clawdbot..."
grep -r "'/tmp'" node_modules/@anthropic-ai/clawdbot/ 2>/dev/null | head -10 || echo "Not found in @anthropic-ai"
grep -r '"tmp"' node_modules/@anthropic-ai/clawdbot/ 2>/dev/null | head -10 || echo "Not found"
grep -r "os.tmpdir" node_modules/@anthropic-ai/clawdbot/ 2>/dev/null | head -10 || echo "No os.tmpdir found"

echo ""
echo "Searching in other locations..."
grep -r "mkdtemp" node_modules/@anthropic-ai/clawdbot/ 2>/dev/null | head -5 || echo "No mkdtemp found"

echo ""
echo "Checking if we can create /tmp as a symlink..."
# Try to create the directory structure
mkdir -p ~/tmp/clawdbot

# Try using a different approach - set all possible env vars
export TMPDIR="$HOME/tmp"
export TEMP="$HOME/tmp"
export TMP="$HOME/tmp"
export CLAWDBOT_TMP="$HOME/tmp"

echo ""
echo "Environment set:"
echo "  TMPDIR=$TMPDIR"
echo "  TEMP=$TEMP"
echo "  TMP=$TMP"
echo ""

# Try running with explicit node flag
echo "Starting gateway with patched environment..."
node --require ~/patch-tmpdir.js ./node_modules/.bin/clawdbot gateway run 2>&1 &
PID=$!

echo "PID: $PID"
sleep 5

if ps | grep -q "$PID"; then
    echo "✓ Gateway is running!"
else
    echo "✗ Failed to start"
fi
