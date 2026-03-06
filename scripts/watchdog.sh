#!/usr/bin/env bash
# watchdog.sh — Fast multi-service watchdog for the Pixel edge server
#
# Runs every 2 minutes via systemd timer (installed by setup-watchdog.sh).
# No AI — pure bash, sub-second per check. Catches port death and dead
# Docker containers and restarts them immediately without waiting for the
# 10-min orchestrator or 30-min heartbeat.
#
# Services watched:
#   claude-gateway    port 3456   systemd user service
#   openclaw-gateway  port 18789  systemd user service
#   llama-server      port 8080   systemd user service (optional)
#   ollama            port 11434  Docker container (optional)
#   jellyfin          port 8096   Docker container (optional)
#
# Deployed by: bash scripts/setup-watchdog.sh

set -uo pipefail

LOG="${HOME}/watchdog/watchdog.log"
MAX_LOG_LINES=600
RECOVERY_WAIT=4   # seconds to wait after a restart before re-checking

mkdir -p "$(dirname "${LOG}")"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "${LOG}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

port_alive() {
  local port="$1"
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -q ":${port} "
  elif command -v nc &>/dev/null; then
    nc -z 127.0.0.1 "${port}" 2>/dev/null
  else
    # last resort: /proc/net/tcp (hex port)
    printf '%04X' "${port}" | xargs -I{} grep -q " {}:" /proc/net/tcp 2>/dev/null
  fi
}

service_active() {
  systemctl --user is-active "${1}.service" 2>/dev/null | grep -q "^active"
}

service_exists() {
  systemctl --user list-unit-files "${1}.service" 2>/dev/null | grep -q "${1}"
}

restart_service() {
  local name="$1"
  systemctl --user restart "${name}.service" 2>/dev/null
}

docker_running() {
  docker inspect --format='{{.State.Status}}' "${1}" 2>/dev/null | grep -q "^running"
}

docker_exists() {
  docker inspect "${1}" &>/dev/null
}

# ── Check + heal a systemd service ───────────────────────────────────────────

check_service() {
  local name="$1" port="$2"
  if ! port_alive "${port}"; then
    log "DEAD: ${name} (port ${port}) — restarting"
    restart_service "${name}"
    sleep "${RECOVERY_WAIT}"
    if port_alive "${port}"; then
      log "  RECOVERED: ${name}"
      return 0
    else
      log "  FAILED: ${name} still not listening on ${port}"
      return 1
    fi
  fi
}

# ── Check + heal a Docker container ──────────────────────────────────────────

check_container() {
  local name="$1" port="$2"
  if ! docker_exists "${name}"; then return 0; fi  # container not created yet
  if ! docker_running "${name}"; then
    local status
    status=$(docker inspect --format='{{.State.Status}}' "${name}" 2>/dev/null || echo "unknown")
    log "DEAD: docker/${name} (${status}) — starting"
    docker start "${name}" >>"${LOG}" 2>&1
    sleep "${RECOVERY_WAIT}"
    if docker_running "${name}"; then
      log "  RECOVERED: docker/${name}"
      return 0
    else
      log "  FAILED: docker/${name} still not running"
      return 1
    fi
  fi
}

# ── Main: check all services ──────────────────────────────────────────────────

ACTED=0

# Critical systemd services
check_service "claude-gateway"   3456 || ACTED=1
check_service "openclaw-gateway" 18789 || ACTED=1

# Optional: llama-server (only if its unit file is installed)
if service_exists "llama-server"; then
  check_service "llama-server" 8080 || ACTED=1
fi

# Optional: Docker containers (only if Docker daemon is accessible)
if docker info &>/dev/null 2>&1; then
  check_container "ollama"   11434 || ACTED=1
  check_container "jellyfin" 8096  || ACTED=1
fi

# ── Log "all OK" once per hour (on the :00 run) to show watchdog is alive ────
if [[ "${ACTED}" -eq 0 ]]; then
  MINUTE=$(date '+%M')
  if [[ "${MINUTE}" -lt 2 ]]; then
    log "OK: all services alive"
  fi
fi

# ── Log rotation ──────────────────────────────────────────────────────────────
if [[ -f "${LOG}" ]]; then
  LINE_COUNT=$(wc -l <"${LOG}" 2>/dev/null || echo 0)
  if (( LINE_COUNT > MAX_LOG_LINES )); then
    TMPFILE=$(mktemp)
    tail -n 100 "${LOG}" >"${TMPFILE}"
    mv "${TMPFILE}" "${LOG}"
  fi
fi
