#!/data/data/com.termux/files/usr/bin/bash
# Jarvy Daemon - Auto-restart on crash
# Run this in Termux to keep the bot always running

BOT_NAME="jarvy"
LOG_FILE="$HOME/tmp/jarvy-daemon.log"
MAX_RESTARTS=10
RESTART_DELAY=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

start_bot() {
    log "Starting $BOT_NAME..."
    cd "$HOME/JARVIS"
    export HOME=/data/data/com.termux/files/home
    export PATH=/data/data/com.termux/files/usr/bin:$PATH
    export TMPDIR=/data/data/com.termux/files/home/tmp
    
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
            log "$BOT_NAME is already running"
            sleep 30
            continue
        fi
        
        # Check if we exceeded max restarts
        if [ $restarts -ge $MAX_RESTARTS ]; then
            log "ERROR: Max restarts ($MAX_RESTARTS) exceeded. Waiting 5 minutes..."
            sleep 300
            restarts=0
            continue
        fi
        
        # Start the bot
        ((restarts++))
        log "Restart $restarts/$MAX_RESTARTS"
        start_bot &
        
        # Wait for it to crash or be killed
        wait
        
        log "$BOT_NAME exited with code $?. Restarting in $RESTART_DELAY seconds..."
        sleep $RESTART_DELAY
    done
}

# Kill existing instances
log "Killing existing $BOT_NAME processes..."
pkill -9 -f clawdbot 2>/dev/null || true
sleep 2

# Start monitoring
log "Starting $BOT_NAME daemon..."
monitor
