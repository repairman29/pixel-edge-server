#!/data/data/com.termux/files/usr/bin/bash

set -u

TERMUX_HOME="/data/data/com.termux/files/home"
PREFIX="/data/data/com.termux/files/usr"
JARVIS_DIR="$TERMUX_HOME/JARVIS"
TMP_DIR="$TERMUX_HOME/tmp"
CLAWDBOT_DIR="$TERMUX_HOME/.clawdbot"
ENV_FILE="$CLAWDBOT_DIR/.env"
SESSIONS_FILE="$CLAWDBOT_DIR/agents/main/sessions/sessions.json"
BOOT_LOG="$TERMUX_HOME/jarvis-autoboot.log"
NODE="$PREFIX/bin/node"
DISCORD_USER_ID_DEFAULT="377601792764018698"

mkdir -p "$TMP_DIR" "$CLAWDBOT_DIR" "$TERMUX_HOME/jarvis-workspace"
touch "$BOOT_LOG"
exec >> "$BOOT_LOG" 2>&1

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

export HOME="$TERMUX_HOME"
export PATH="$PREFIX/bin:$PATH"
export TMPDIR="$TMP_DIR"
export TMP="$TMP_DIR"
export TEMP="$TMP_DIR"

log "autoboot start"

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock >/dev/null 2>&1 || true
fi

if [ ! -d "$JARVIS_DIR" ]; then
  log "JARVIS repo missing at $JARVIS_DIR"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  touch "$ENV_FILE"
fi

# Remove Telegram token if present
if /data/data/com.termux/files/usr/bin/grep -q '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null; then
  /data/data/com.termux/files/usr/bin/grep -v '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  log "removed TELEGRAM_BOT_TOKEN from .env"
fi

if [ -z "$(/data/data/com.termux/files/usr/bin/grep '^DISCORD_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null)" ]; then
  log "warning: DISCORD_BOT_TOKEN is missing from $ENV_FILE"
fi

# Normalize clawdbot config
"$NODE" - <<'EOF'
const fs = require('fs');
const path = require('path');

const home = '/data/data/com.termux/files/home';
const configPath = path.join(home, '.clawdbot', 'clawdbot.json');

let config = {};
if (fs.existsSync(configPath)) {
  try { config = JSON.parse(fs.readFileSync(configPath, 'utf8')); } catch { config = {}; }
}

config.gateway = { ...(config.gateway || {}), mode: 'local', port: 18789, bind: 'lan' };

config.logging = {
  ...(config.logging || {}),
  file: '/data/data/com.termux/files/home/tmp/clawdbot.log',
};

config.plugins = {
  ...(config.plugins || {}),
  entries: {
    ...(((config.plugins || {}).entries) || {}),
    telegram: { enabled: false },
    discord: { ...((((config.plugins || {}).entries) || {}).discord || {}), enabled: true },
  },
};

if (config.discord) delete config.discord;

config.session = { ...(config.session || {}), dmScope: 'per-channel-peer' };

// Use built-in ollama provider — ollama-proxy.js forwards 11434 → 8889 (Ragionare)
config.models = {
  providers: {
    ollama: {
      baseUrl: "http://127.0.0.1:11434",
      models: [
        { id: "Granite 4.0 Helper 1B", name: "Granite 4.0 Helper 1B", contextWindow: 8192 }
      ]
    }
  }
};

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
// Granite 4.0 Helper 1B: fastest reliable local model on this device
// Ollama model name (no prefix needed — clawdbot auto-detects ollama provider)
config.agents.defaults.model = { primary: 'ollama/Granite 4.0 Helper 1B' };
config.agents.defaults.bootstrapMaxChars = 500;
// Empty workspace — no markdown files to inject into the prompt
config.agents.defaults.workspace = '/data/data/com.termux/files/home/jarvis-workspace';

fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', 'utf8');
EOF

log "normalized clawdbot config"

# Wipe any workspace markdown that was auto-generated (keeps prompt small)
rm -f "$TERMUX_HOME/jarvis-workspace"/*.md 2>/dev/null || true

# Kill stale processes
pkill -f 'clawdbot gateway' 2>/dev/null || true
pkill -f 'gateway run' 2>/dev/null || true
pkill -f 'ollama-proxy' 2>/dev/null || true
pkill -f 'pixel-chat-server' 2>/dev/null || true
sleep 2

# Start Ragionare→Ollama proxy (forwards 11434 → 8889)
# This lets the built-in clawdbot Ollama provider find Ragionare
PROXY_SCRIPT="$JARVIS_DIR/scripts/ollama-proxy.js"
if [ -f "$PROXY_SCRIPT" ]; then
  nohup "$NODE" "$PROXY_SCRIPT" >> "$TMP_DIR/ollama-proxy.log" 2>&1 &
  log "ollama-proxy spawned on :11434 → :8889 (PID $!)"
  sleep 1
else
  log "warning: ollama-proxy.js not found"
fi

# Proot network patch
PATCH_PATH="$JARVIS_DIR/scripts/patch-proot-network.js"
if [ -f "$PATCH_PATH" ]; then
  export NODE_OPTIONS="${NODE_OPTIONS:-} --require $PATCH_PATH"
fi

export PORT=18789
export BIND_LAN=1

# Start gateway
cd "$JARVIS_DIR"
nohup "$NODE" scripts/start-gateway-background.js >> "$TERMUX_HOME/gateway.log" 2>&1 &
log "gateway spawned (PID $!)"

# Start chat server
nohup "$NODE" scripts/pixel-chat-server.js >> "$TERMUX_HOME/chat-server.log" 2>&1 &
log "chat server spawned (PID $!)"

# Link Discord session alias to main session if both exist
DISCORD_USER_ID="$DISCORD_USER_ID_DEFAULT"
if [ -f "$ENV_FILE" ]; then
  env_id="$(/data/data/com.termux/files/usr/bin/grep '^JARVIS_DISCORD_USER_ID=' "$ENV_FILE" 2>/dev/null | /data/data/com.termux/files/usr/bin/cut -d= -f2-)"
  [ -n "$env_id" ] && DISCORD_USER_ID="$env_id"
fi

if [ -f "$SESSIONS_FILE" ]; then
  _sf="$SESSIONS_FILE"
  _du="$DISCORD_USER_ID"
  "$NODE" -e "
const fs = require('fs');
const p = process.argv[1];
const discordUserId = process.argv[2];
const mainKey = 'agent:main:main';
const aliasKey = 'agent:main:' + discordUserId;
let data;
try { data = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { process.exit(0); }
if (data[mainKey] && data[aliasKey]) {
  data[aliasKey] = { ...data[aliasKey], sessionId: data[mainKey].sessionId, sessionFile: data[mainKey].sessionFile };
  fs.writeFileSync(p, JSON.stringify(data, null, 2) + '\n', 'utf8');
}
" -- "$_sf" "$_du" || true
fi

# Wait for gateway to come up
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  code="$(/data/data/com.termux/files/usr/bin/curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/ 2>/dev/null || printf '000')"
  if [ "$code" = "200" ]; then
    log "gateway healthy on attempt $i"
    break
  fi
  sleep 5
done

gw_code="$(/data/data/com.termux/files/usr/bin/curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/ 2>/dev/null || printf '000')"
proxy_code="$(/data/data/com.termux/files/usr/bin/curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:11434/api/tags 2>/dev/null || printf '000')"
log "final status gateway=$gw_code ollama-proxy=$proxy_code"

log "autoboot done"
