#!/data/data/com.termux/files/usr/bin/bash
# Daemonizes the clawdbot gateway using setsid.
# Run from ADB: run-as com.termux /data/data/com.termux/files/home/launch-gateway.sh

H=/data/data/com.termux/files/home
P=/data/data/com.termux/files/usr

export HOME=$H
export PATH=$P/bin:$PATH
export TMPDIR=$H/tmp
export TMP=$H/tmp
export TEMP=$H/tmp
export PORT=18789
export BIND_LAN=1

# Load .env (DISCORD_BOT_TOKEN, GROQ_API_KEY, etc.) — skip lines that would cause parse errors
if [ -f "$H/.clawdbot/.env" ]; then
  while IFS= read -r line; do
    case "$line" in
      \#*|'') continue ;;
      *=*) 
        key="${line%%=*}"
        val="${line#*=}"
        # Only export simple variable names, skip lines with shell metacharacters in value
        case "$key" in *[!A-Za-z0-9_]*) continue ;; esac
        export "$key=$val" 2>/dev/null || true
        ;;
    esac
  done < "$H/.clawdbot/.env"
fi

mkdir -p $H/tmp

# Kill any existing gateway
$P/bin/pkill -f 'clawdbot gateway' 2>/dev/null || true
$P/bin/pkill -f 'gateway run --allow-unconfigured' 2>/dev/null || true
sleep 1

LOG=$H/gateway.log
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] launch-gateway: starting" >> $LOG

JARVIS=$H/JARVIS

# nohup + & in a Termux shell keeps the process alive after the parent exits.
# We redirect to the log file so stdout/stderr don't cause EPIPE when the adb pipe closes.
cd $JARVIS
nohup $P/bin/node $JARVIS/scripts/start-gateway-background.js >> $LOG 2>&1 &
GW_PID=$!
echo $GW_PID > $H/tmp/gw-launcher.pid
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] launch-gateway: launcher PID=$GW_PID" >> $LOG

# Wait for launcher to exit (it exits quickly after forking the gateway)
wait $GW_PID 2>/dev/null

# Now check what gateway process was spawned
sleep 3
GW_ACTUAL=$(cat $H/tmp/gateway.pid 2>/dev/null || echo "unknown")
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] launch-gateway: gateway PID=$GW_ACTUAL" >> $LOG
