#!/data/data/com.termux/files/usr/bin/bash

TERMUX_HOME="/data/data/com.termux/files/home"
PREFIX="/data/data/com.termux/files/usr"
HEALTH_LOG="$TERMUX_HOME/jarvis-keepalive.log"
START_SCRIPT="$TERMUX_HOME/pixel-jarvis-autoboot.sh"

mkdir -p "$TERMUX_HOME/tmp"
touch "$HEALTH_LOG"
exec >> "$HEALTH_LOG" 2>&1

export HOME="$TERMUX_HOME"
export PATH="$PREFIX/bin:$PATH"
export TMPDIR="$TERMUX_HOME/tmp"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

gateway_code="$(/data/data/com.termux/files/usr/bin/curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/ 2>/dev/null || printf '000')"
chat_code="$(/data/data/com.termux/files/usr/bin/curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18888/ 2>/dev/null || printf '000')"

if pgrep -f 'clawdbot-gateway' >/dev/null 2>&1 && [ "$gateway_code" = "200" ] && [ "$chat_code" = "200" ]; then
  log "healthy gateway=$gateway_code chat=$chat_code"
  exit 0
fi

log "unhealthy gateway=$gateway_code chat=$chat_code -- restarting"
/data/data/com.termux/files/usr/bin/bash "$START_SCRIPT"
