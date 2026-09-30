#!/data/data/com.termux/files/usr/bin/bash
# Termux Boot Script - Auto-start Jarvy on device boot
# Copy to: ~/.termux/boot/start-jarvy

# Wait for Termux to fully initialize
sleep 5

# Set environment
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/home/tmp

# Ensure directories exist
mkdir -p "$HOME/tmp"
mkdir -p "$HOME/.clawdbot"

# Start the daemon
cd "$HOME"
nohup bash jarvy-daemon.sh >> "$HOME/tmp/jarvy-boot.log" 2>&1 &

# Log startup
echo "[$(date)] Jarvy daemon started on boot" >> "$HOME/tmp/jarvy-boot.log"
