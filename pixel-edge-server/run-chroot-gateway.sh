#!/data/data/com.termux/files/usr/bin/bash
# Run clawdbot in chroot environment

echo "=== Starting Clawdbot in Chroot ==="
echo ""

# Kill existing
pkill -9 -f clawdbot 2>/dev/null
sleep 2

# Apply miniCPM4 config
~/config-minicpm4-pixel.sh

echo "Starting in chroot..."
echo ""

# Run in chroot which has /tmp
termux-chroot bash -c '
    mkdir -p /tmp/clawdbot
    cd ~/JARVIS
    ./node_modules/.bin/clawdbot gateway run --allow-unconfigured --port 18789 --bind lan 2>&1 | tee ~/chroot-gateway.log
'
