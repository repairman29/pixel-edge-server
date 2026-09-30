#!/data/data/com.termux/files/usr/bin/bash

TERMUX_HOME="/data/data/com.termux/files/home"
PREFIX="/data/data/com.termux/files/usr"
AUTOSTART="$TERMUX_HOME/pixel-jarvis-autoboot.sh"
KEEPALIVE="$TERMUX_HOME/pixel-jarvis-keepalive.sh"
SUPERVISOR_LOG="$TERMUX_HOME/jarvis-supervisor.log"

mkdir -p "$TERMUX_HOME/tmp"
touch "$SUPERVISOR_LOG"
exec >> "$SUPERVISOR_LOG" 2>&1

export HOME="$TERMUX_HOME"
export PATH="$PREFIX/bin:$PATH"
export TMPDIR="$TERMUX_HOME/tmp"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log "supervisor boot"
/data/data/com.termux/files/usr/bin/bash "$AUTOSTART"

while true; do
  sleep 300
  /data/data/com.termux/files/usr/bin/bash "$KEEPALIVE"
done
