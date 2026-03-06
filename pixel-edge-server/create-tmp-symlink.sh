#!/data/data/com.termux/files/usr/bin/bash
# Create /tmp symlink for clawdbot

echo "Creating /tmp symlink..."

# Try to create symlink (may need to use different location)
if [ ! -d "/tmp" ]; then
    # Create symlink in Termux's private space
    mkdir -p ~/tmp
    
    # Try to create /tmp as symlink
    ln -s ~/tmp /tmp 2>&1 || {
        echo "Cannot create /tmp symlink (permission denied)"
        echo ""
        echo "Alternative: Create tmp in Termux's data directory"
        mkdir -p /data/data/com.termux/files/usr/tmp
        mkdir -p /data/data/com.termux/files/usr/tmp/clawdbot
        echo "Created: /data/data/com.termux/files/usr/tmp"
    }
fi

echo ""
echo "Checking /tmp..."
ls -la /tmp 2>&1 || echo "/tmp not accessible"

echo ""
echo "Now try: cd ~/JARVIS && ./node_modules/.bin/clawdbot gateway run"
