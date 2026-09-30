#!/data/data/com.termux/files/usr/bin/bash
# Use termux-chroot to create /tmp

echo "=== Using termux-chroot for /tmp ==="
echo ""

# Check if termux-chroot exists
if command -v termux-chroot &> /dev/null; then
    echo "termux-chroot found"
else
    echo "Installing proot..."
    pkg install -y proot
fi

cd ~/JARVIS

echo "Starting gateway with termux-chroot..."
echo ""

# Run in chroot environment which has /tmp
termux-chroot bash -c '
    cd ~/JARVIS
    export PORT=18789
    export BIND_LAN=1
    ./node_modules/.bin/clawdbot gateway run
'
