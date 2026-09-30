#!/data/data/com.termux/files/usr/bin/bash
# Health check for Jarvy - Run via cron every 5 minutes

LOG_FILE="$HOME/tmp/jarvy-health.log"
PID_FILE="$HOME/tmp/jarvy.pid"

check_health() {
    # Check if process exists
    if ! pgrep -f "clawdbot-gateway" > /dev/null; then
        echo "[$(date)] Jarvy not running" >> "$LOG_FILE"
        return 1
    fi
    
    # Check if responding (if netstat available)
    if command -v netstat > /dev/null; then
        if ! netstat -tlnp 2>/dev/null | grep -q ":18790"; then
            echo "[$(date)] Port 18790 not listening" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    # Check log for recent errors
    if [ -f "$HOME/tmp/clawdbot.log" ]; then
        # Check for recent errors in last 5 minutes
        recent_errors=$(tail -100 "$HOME/tmp/clawdbot.log" | grep -c "ERROR\|exception" 2>/dev/null || echo 0)
        if [ "$recent_errors" -gt 5 ]; then
            echo "[$(date)] Too many recent errors: $recent_errors" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    return 0
}

restart_jarvy() {
    echo "[$(date)] Restarting Jarvy..." >> "$LOG_FILE"
    
    # Kill existing
    pkill -9 -f clawdbot 2>/dev/null || true
    sleep 2
    
    # Start fresh
    cd "$HOME/JARVIS"
    export HOME=/data/data/com.termux/files/home
    export PATH=/data/data/com.termux/files/usr/bin:$PATH
    
    nohup node node_modules/clawdbot/dist/entry.js gateway run \
        --port 18790 --bind lan >> "$HOME/tmp/clawdbot.log" 2>&1 &
    
    echo "[$(date)] Jarvy restarted with PID $!" >> "$LOG_FILE"
}

# Main check
if ! check_health; then
    restart_jarvy
fi
