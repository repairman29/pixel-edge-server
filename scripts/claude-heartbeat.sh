#!/usr/bin/env bash
# claude-heartbeat.sh — AI-powered Pixel server health check
#
# Runs on a cron schedule inside the VM.
# Gathers system metrics, submits them to the local Claude Gateway's /v1/agent
# endpoint, and logs the AI health report to ~/claude-gateway/heartbeat.log.
#
# Deployed by: scripts/setup-claude-heartbeat.sh
# Cron schedule: every 30 minutes (configurable below)

set -euo pipefail

# ── Dependency check ───────────────────────────────────────────────────────────
for _cmd in curl jq; do
  command -v "${_cmd}" >/dev/null 2>&1 || { echo "ERROR: required command '${_cmd}' not found. Install it and retry."; exit 1; }
done

GATEWAY_URL="${CLAUDE_GATEWAY_URL:-http://127.0.0.1:3456}"
LOG_FILE="${HOME}/claude-gateway/heartbeat.log"
MAX_LOG_LINES=1000   # rotate when log grows past this

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() { echo "[$(timestamp)] $*" | tee -a "${LOG_FILE}"; }

# ── Collect quick local metrics (fast, no Claude needed) ──────────────────────
UPTIME=$(uptime -p 2>/dev/null || uptime)
MEM=$(free -h | awk '/^Mem:/ {printf "%s used / %s total", $3, $2}')
DISK=$(df -h / | awk 'NR==2 {printf "%s used / %s total (%s)", $3, $2, $5}')
LOAD=$(cat /proc/loadavg | cut -d' ' -f1-3)
THERMAL=$(for z in /sys/class/thermal/thermal_zone*; do
  name=$(cat "$z/type" 2>/dev/null)
  temp=$(cat "$z/temp" 2>/dev/null)
  printf "%s=%.1f°C " "$name" "$(echo "$temp / 1000" | bc -l 2>/dev/null || echo '?')"
done)
DOCKER_RUNNING=$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ' || echo 'docker unavailable')
GATEWAY_UP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${GATEWAY_URL}/health" || echo '000')

# ── Build the task for Claude ─────────────────────────────────────────────────
TASK=$(cat << EOF
You are the autonomous health monitor AND system operator for a Google Pixel 8 Pro
running as an edge AI server. Your job is to diagnose, FIX, and then report.

Pre-collected metrics:
  uptime:         ${UPTIME}
  memory:         ${MEM}
  disk (/):       ${DISK}
  load (1/5/15m): ${LOAD}
  thermal zones:  ${THERMAL}
  docker running: ${DOCKER_RUNNING}
  gateway /health: HTTP ${GATEWAY_UP}

Tasks (complete all before writing the report):
1. Check claude-gateway service: run_shell("systemctl --user status claude-gateway --no-pager -l")
   - If not active, restart it: restart_service("claude-gateway") then verify.
2. Check openclaw-gateway service: run_shell("systemctl --user status openclaw-gateway --no-pager -l")
   - If not active, restart it: restart_service("openclaw-gateway") then verify.
3. Check ports: check_network — confirm 3456 and 18789 are listening.
   - If a port is missing after a restart, note it as CRITICAL.
4. Check thermals: check_thermal — flag anything above 75°C as WARNING, above 85°C as CRITICAL.
5. Check processes: list_processes — flag any single process using >80% CPU.
6. Check disk: check_disk — flag if / is above 85% used.
7. Produce a HEARTBEAT REPORT:
   - STATUS: OK | WARNING | CRITICAL
   - One-line summary
   - Bullet list of findings (services checked, actions taken, resource warnings)
   - If any service was restarted, note it explicitly: "• Restarted <name> (was <state>)"
   - If STATUS is not OK, include a recommended next action
EOF
)

log "─── Heartbeat start ─────────────────────────────────"

# ── Check gateway is up before calling it ─────────────────────────────────────
if [[ "${GATEWAY_UP}" != "200" ]]; then
  log "Gateway unreachable (HTTP ${GATEWAY_UP}) — attempting restart..."
  systemctl --user restart claude-gateway 2>/dev/null || true
  sleep 5
  GATEWAY_UP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${GATEWAY_URL}/health" || echo '000')
  if [[ "${GATEWAY_UP}" != "200" ]]; then
    log "CRITICAL: Claude Gateway still down after restart attempt. Skipping AI analysis."
    exit 1
  fi
  log "Gateway recovered (HTTP ${GATEWAY_UP})."
fi

# ── Submit agentic task to local Claude Gateway ───────────────────────────────
log "Submitting health task to Claude (model: claude-opus-4-6)..."

RESPONSE=$(curl -s -X POST "${GATEWAY_URL}/v1/agent" \
  -H "Content-Type: application/json" \
  --max-time 120 \
  -d "$(jq -n --arg task "${TASK}" '{task: $task, max_turns: 16}')" 2>/dev/null)

if [[ -z "${RESPONSE}" ]]; then
  log "ERROR: Empty response from gateway."
  exit 1
fi

RESULT=$(echo "${RESPONSE}" | jq -r '.result // "No result returned."' 2>/dev/null)
TURNS=$(echo "${RESPONSE}"  | jq -r '.turns // "?"' 2>/dev/null)

log "Heartbeat complete (${TURNS} agent turns)."
log ""
log "${RESULT}"
log ""

# ── Rotate log if it's grown too large ────────────────────────────────────────
LINE_COUNT=$(wc -l < "${LOG_FILE}" 2>/dev/null || echo 0)
if (( LINE_COUNT > MAX_LOG_LINES )); then
  TMPFILE=$(mktemp "${LOG_FILE}.XXXXXX")
  trap 'rm -f "${TMPFILE}"' EXIT
  tail -n "${MAX_LOG_LINES}" "${LOG_FILE}" > "${TMPFILE}"
  mv -f "${TMPFILE}" "${LOG_FILE}"
  trap - EXIT
fi

log "─── Heartbeat end ───────────────────────────────────"
