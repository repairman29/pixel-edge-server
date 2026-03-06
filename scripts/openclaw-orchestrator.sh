#!/usr/bin/env bash
# openclaw-orchestrator.sh — OpenClaw-driven agentic system management
#
# This is the "OpenClaw calling the shots" loop.
#
# Runs every 10 minutes via systemd timer (installed by setup-openclaw-orchestrator.sh).
# OpenClaw dispatches a comprehensive management task to Claude Gateway's /v1/agent
# endpoint. Claude has full tool authority: it checks every service, restarts anything
# broken, verifies recovery, monitors resources, and writes a structured status file
# that OpenClaw can surface.
#
# Flow:
#   [timer] → openclaw-orchestrator.sh
#               → POST /v1/agent  (task: manage + fix the whole stack)
#                   → Claude uses: run_shell, restart_service, http_fetch,
#                                  check_thermal, check_disk, list_processes,
#                                  read_file, write_file
#               ← result (what was found and fixed)
#               → ~/openclaw-orchestrator/status.md  (machine-readable, for OpenClaw UI)
#               → ~/openclaw-orchestrator/orchestrator.log
#
# Deployed by: bash scripts/setup-openclaw-orchestrator.sh

set -uo pipefail

GATEWAY="${CLAUDE_GATEWAY_URL:-http://127.0.0.1:3456}"
STATUS_FILE="${HOME}/openclaw-orchestrator/status.md"
LOG_FILE="${HOME}/openclaw-orchestrator/orchestrator.log"
MAX_LOG_LINES=800
MAX_TURNS=25
TIMEOUT=180   # seconds to wait for Claude to complete the task

mkdir -p "$(dirname "${STATUS_FILE}")"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "${LOG_FILE}"; }

# ── Log rotation ───────────────────────────────────────────────────────────────
if [[ -f "${LOG_FILE}" ]]; then
  LINE_COUNT=$(wc -l <"${LOG_FILE}" 2>/dev/null || echo 0)
  if (( LINE_COUNT > MAX_LOG_LINES )); then
    TMPFILE=$(mktemp)
    tail -n 200 "${LOG_FILE}" >"${TMPFILE}"
    mv "${TMPFILE}" "${LOG_FILE}"
  fi
fi

log "━━━ Orchestrator run ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Ensure Claude Gateway is reachable before dispatching ─────────────────────
GW_STATUS=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 4 "${GATEWAY}/health" 2>/dev/null || echo "000")

if [[ "${GW_STATUS}" != "200" ]]; then
  log "WARN: Claude Gateway unreachable (HTTP ${GW_STATUS}) — attempting self-restart"
  systemctl --user restart claude-gateway.service 2>/dev/null || true
  sleep 6
  GW_STATUS=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 5 "${GATEWAY}/health" 2>/dev/null || echo "000")
  if [[ "${GW_STATUS}" != "200" ]]; then
    log "CRITICAL: Claude Gateway still down. Orchestrator cannot dispatch. Exiting."
    # Write a minimal status file so OpenClaw knows something is wrong
    cat > "${STATUS_FILE}" <<EOF
# System Status — $(ts)

**Overall: CRITICAL**

Claude Gateway is unreachable (HTTP ${GW_STATUS}). Orchestrator could not run.

Manual action needed:
\`\`\`
systemctl --user restart claude-gateway
journalctl --user -u claude-gateway -n 30
\`\`\`
EOF
    exit 1
  fi
  log "Claude Gateway recovered (HTTP ${GW_STATUS})."
fi

# ── Collect fast local context to pass to Claude ──────────────────────────────
UPTIME=$(uptime -p 2>/dev/null || uptime)
MEM=$(free -h 2>/dev/null | awk '/^Mem:/ {printf "%s used / %s total (avail: %s)", $3, $2, $7}' || echo "unavailable")
DISK=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s used / %s total (%s)", $3, $2, $5}' || echo "unavailable")
DOCKER_UP=$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ' || echo "docker unavailable")

# ── Build the management task ──────────────────────────────────────────────────
TASK=$(cat <<TASK_EOF
You are the autonomous system manager for a Pixel 8 Pro running as an edge AI server.
OpenClaw has dispatched you to perform a full management cycle. You have complete
authority to check and fix anything that is wrong.

Pre-collected context (gathered before this task):
  uptime:         ${UPTIME}
  memory:         ${MEM}
  disk (/):       ${DISK}
  docker running: ${DOCKER_UP}

YOUR MANAGEMENT TASKS (complete all of these):

1. SERVICE HEALTH — CHECK AND FIX
   For each service below, check status AND verify the port is listening.
   If a service is NOT active+running, restart it, wait 4 seconds, verify recovery.

   Critical services (always check):
     - claude-gateway     → port 3456  → restart: restart_service("claude-gateway")
     - openclaw-gateway   → port 18789 → restart: restart_service("openclaw-gateway")

   Optional services (check only if unit file exists):
     - llama-server  → port 8080 → restart: restart_service("llama-server")

   Docker containers (check if docker is available):
     - ollama    → port 11434 → restart: run_shell("docker start ollama")
     - jellyfin  → port 8096  → restart: run_shell("docker start jellyfin")

   For each: run_shell("ss -tlnp 2>/dev/null | grep :<port>") to verify port.

2. RESOURCE MONITORING
   a. Thermal: use check_thermal — flag any zone above 70°C as WARNING, above 80°C as CRITICAL
   b. Disk: use check_disk — flag if / is above 80% used. If above 90%, identify and clean:
      - run_shell("journalctl --user --disk-usage") — vacuum if logs exceed 200MB
      - run_shell("docker system df 2>/dev/null") — note build cache usage
      - run_shell("du -sh ~/llama-models/* 2>/dev/null | sort -h | tail -5") if llama-models exists
   c. Memory: run_shell("free -h") — flag if available < 500MB
   d. Load: run_shell("cat /proc/loadavg") — flag if 1-min load > 6.0

3. LOG MAINTENANCE
   a. Check heartbeat log size: run_shell("wc -l ~/claude-gateway/heartbeat.log 2>/dev/null || echo 0")
      If > 800 lines: run_shell("tail -n 200 ~/claude-gateway/heartbeat.log > /tmp/hb.tmp && mv /tmp/hb.tmp ~/claude-gateway/heartbeat.log")
   b. Check watchdog log size: run_shell("wc -l ~/watchdog/watchdog.log 2>/dev/null || echo 0")
      If > 600 lines: run_shell("tail -n 100 ~/watchdog/watchdog.log > /tmp/wd.tmp && mv /tmp/wd.tmp ~/watchdog/watchdog.log")

4. WRITE STATUS FILE
   After completing all checks and fixes, write a structured status report to
   ~/openclaw-orchestrator/status.md in exactly this format:

   # System Status — <timestamp>

   **Overall: OK | WARNING | CRITICAL**

   ## Services
   | Service | State | Port | Note |
   |---------|-------|------|------|
   | claude-gateway | active ✓ | 3456 ✓ | |
   | openclaw-gateway | active ✓ | 18789 ✓ | |
   | llama-server | not installed | 8080 — | |
   | ollama (docker) | running ✓ | 11434 ✓ | |
   | jellyfin (docker) | running ✓ | 8096 ✓ | |

   ## Resources
   - Thermal: (summary — any warnings?)
   - Disk /: (used/total, % — any warnings?)
   - Memory: (available — any warnings?)
   - Load: (1/5/15m averages — any warnings?)

   ## Actions Taken
   - (list every restart or fix performed, e.g. "Restarted openclaw-gateway (was crashed)")
   - (or "None — all services were healthy")

   ## Next Run
   ~10 minutes

5. Return the contents of ~/openclaw-orchestrator/status.md as your final response.
TASK_EOF
)

# ── Dispatch to Claude Gateway ─────────────────────────────────────────────────
log "Dispatching management task to Claude Gateway (max ${MAX_TURNS} turns, ${TIMEOUT}s timeout)..."

RESPONSE=$(curl -sf \
  -X POST "${GATEWAY}/v1/agent" \
  -H "Content-Type: application/json" \
  --max-time "${TIMEOUT}" \
  -d "$(jq -n \
       --arg task "${TASK}" \
       --argjson max_turns "${MAX_TURNS}" \
       '{task: $task, max_turns: $max_turns}')" \
  2>/dev/null)

EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]] || [[ -z "${RESPONSE}" ]]; then
  log "ERROR: Agent call failed (exit ${EXIT_CODE}, response empty? $([[ -z "${RESPONSE}" ]] && echo yes || echo no))"
  exit 1
fi

TURNS=$(echo "${RESPONSE}" | jq -r '.turns // "?"' 2>/dev/null)
RESULT=$(echo "${RESPONSE}" | jq -r '.result // "No result returned."' 2>/dev/null)

log "Task complete — ${TURNS} agent turns."

# ── Ensure status file was written (fallback if Claude didn't write it) ────────
if [[ ! -f "${STATUS_FILE}" ]] || [[ "$(find "${STATUS_FILE}" -mmin +12 2>/dev/null)" ]]; then
  log "WARN: Status file not updated by Claude — writing fallback"
  cat > "${STATUS_FILE}" <<EOF
# System Status — $(ts)

**Overall: UNKNOWN** (status file was not written by Claude this run)

## Agent Result
${RESULT}

## Turns
${TURNS}
EOF
fi

# ── Summarize result in log ────────────────────────────────────────────────────
OVERALL=$(grep -m1 '^\*\*Overall:' "${STATUS_FILE}" 2>/dev/null | sed 's/\*\*//g' || echo "Unknown")
log "Status: ${OVERALL}"
log "━━━ Orchestrator run end ━━━━━━━━━━━━━━━━━━━━━━━━━"
