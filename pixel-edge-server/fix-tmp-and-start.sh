#!/data/data/com.termux/files/usr/bin/bash
# Fix /tmp issue for clawdbot on Android

echo "=== Fixing /tmp for Clawdbot ==="
echo ""

# Check if /tmp exists
if [ -d "/tmp" ]; then
    echo "/tmp exists"
    ls -la /tmp 2>&1 | head -5
else
    echo "/tmp does not exist, creating symlink..."
    # Try to create symlink (may need root)
    ln -s ~/tmp /tmp 2>&1 || echo "Cannot create /tmp symlink"
fi

echo ""
echo "Creating clawdbot temp directory..."
mkdir -p ~/tmp/clawdbot
ls -la ~/tmp/clawdbot 2>&1 | head -3

echo ""
echo "Setting TMPDIR..."
export TMPDIR=~/tmp
export TEMP=~/tmp
export TMP=~/tmp

echo "  TMPDIR=$TMPDIR"
echo "  TEMP=$TEMP"
echo "  TMP=$TMP"
echo ""

echo "Starting gateway..."
cd ~/JARVIS
./node_modules/.bin/clawdbot gateway run 2>&1
