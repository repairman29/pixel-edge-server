#!/data/data/com.termux/files/usr/bin/bash
# Setup Resilient Jarvy - One-time setup script

set -e

echo "=== Jarvy Resilience Setup ==="

# Configuration
JARVIS_DIR="$HOME/JARVIS"
CONFIG_DIR="$HOME/.clawdbot"
BOOT_DIR="$HOME/.termux/boot"
TMP_DIR="$HOME/tmp"

# Create directories
echo "[1/6] Creating directories..."
mkdir -p "$TMP_DIR"
mkdir -p "$BOOT_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/agents/main/agent"

# Create auth file if missing
echo "[2/6] Setting up authentication..."
if [ ! -f "$CONFIG_DIR/agents/main/agent/auth-profiles.json" ]; then
    cat > "$CONFIG_DIR/agents/main/agent/auth-profiles.json" << 'EOF'
{
  "farm": {
    "apiKey": "sk-local-farm"
  }
}
EOF
fi

# Copy daemon script
echo "[3/6] Installing daemon..."
cat > "$HOME/jarvy-daemon.sh" << 'DAEMON_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Jarvy Daemon - Auto-restart on crash

BOT_NAME="jarvy"
LOG_FILE="$HOME/tmp/jarvy-daemon.log"
MAX_RESTARTS=10
RESTART_DELAY=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

start_bot() {
    log "Starting $BOT_NAME..."
    cd "$HOME/JARVIS"
    export HOME=/data/data/com.termux/files/home
    export PATH=/data/data/com.termux/files/usr/bin:$PATH
    export TMPDIR=/data/data/com.termux/files/home/tmp
    
    # Ensure log file exists
    touch "$HOME/tmp/clawdbot.log"
    
    # Start clawdbot gateway
    exec node node_modules/clawdbot/dist/entry.js gateway run \
        --port 18790 \
        --bind lan \
        >> "$HOME/tmp/clawdbot.log" 2>&1
}

monitor() {
    local restarts=0
    
    while true; do
        # Check if already running
        if pgrep -f "clawdbot-gateway" > /dev/null; then
            sleep 30
            continue
        fi
        
        if [ $restarts -ge $MAX_RESTARTS ]; then
            log "Max restarts exceeded. Waiting 5 minutes..."
            sleep 300
            restarts=0
            continue
        fi
        
        ((restarts++))
        log "Restart $restarts/$MAX_RESTARTS"
        start_bot &
        wait
        log "$BOT_NAME exited. Restarting in $RESTART_DELAY seconds..."
        sleep $RESTART_DELAY
    done
}

# Kill existing
pkill -9 -f clawdbot 2>/dev/null || true
sleep 2

# Start monitoring
log "Starting $BOT_NAME daemon..."
monitor
DAEMON_EOF

chmod +x "$HOME/jarvy-daemon.sh"

# Create boot script
echo "[4/6] Setting up auto-start on boot..."
cat > "$BOOT_DIR/start-jarvy" << 'BOOT_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Auto-start Jarvy on boot
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH

# Wait for system to settle
sleep 10

# Start the daemon
nohup "$HOME/jarvy-daemon.sh" > "$HOME/tmp/jarvy-boot.log" 2>&1 &
BOOT_EOF

chmod +x "$BOOT_DIR/start-jarvy"

# Create status script
echo "[5/6] Creating status script..."
cat > "$HOME/jarvy-status.sh" << 'STATUS_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Check Jarvy status

echo "=== Jarvy Status ==="
echo ""

# Check processes
echo "Running Processes:"
ps | grep -E "claw|jarvy" || echo "  None"
echo ""

# Check port
echo "Port Status:"
netstat -tlnp 2>/dev/null | grep 18790 || echo "  Port 18790 not listening"
echo ""

# Check logs
echo "Recent Logs:"
tail -20 "$HOME/tmp/clawdbot.log" 2>/dev/null | grep -E "(discord|logged|error|ERROR)" | head -5 || echo "  No recent activity"
echo ""

# Check Discord status
echo "Discord Status:"
if grep "logged in to discord" "$HOME/tmp/clawdbot.log" 2>/dev/null | tail -1 | grep -q "1478435625266053333"; then
    echo "  ✅ Bot logged in as 1478435625266053333"
else
    echo "  ❌ Bot not logged in"
fi
echo ""

echo "=== Quick Commands ==="
echo "Start: ~/jarvy-daemon.sh &"
echo "Stop: pkill -9 -f clawdbot"
echo "Logs: tail -f ~/tmp/clawdbot.log"
echo "Status: ~/jarvy-status.sh"
STATUS_EOF

chmod +x "$HOME/jarvy-status.sh"

# Create manual start script
echo "[6/6] Creating manual start script..."
cat > "$HOME/start-jarvy-now.sh" << 'START_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Start Jarvy immediately

echo "Starting Jarvy..."

# Kill existing
pkill -9 -f clawdbot 2>/dev/null || true
sleep 2

# Start daemon
nohup "$HOME/jarvy-daemon.sh" > "$HOME/tmp/jarvy-daemon.log" 2>&1 &

echo "Jarvy daemon started!"
echo ""
echo "Check status: ~/jarvy-status.sh"
echo "View logs: tail -f ~/tmp/clawdbot.log"
START_EOF

chmod +x "$HOME/start-jarvy-now.sh"

echo ""
echo "✅ Setup Complete!"
echo ""
echo "To start Jarvy now, run:"
echo "  ~/start-jarvy-now.sh"
echo ""
echo "The bot will auto-start on device boot via Termux boot script."
echo ""
echo "Useful commands:"
echo "  ~/jarvy-status.sh     - Check status"
echo "  ~/start-jarvy-now.sh  - Start manually"
echo "  pkill -9 -f clawdbot - Stop"
echo ""
