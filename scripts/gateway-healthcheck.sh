#!/usr/bin/env bash
# Run inside the Pixel VM. Checks that the gateway is listening on 18789; restarts if not.
# Used by systemd timer every 5 min.

set -e

LOG="${HOME}/openclaw-heartbeat/gateway-healthcheck.log"
mkdir -p "$(dirname "$LOG")"

# Gateway listens on 18789; if nothing is listening, restart the service
if command -v ss >/dev/null 2>&1; then
  if ss -tlnp 2>/dev/null | grep -q ':18789 '; then
    echo "$(date -Iseconds) OK" >> "$LOG"
    exit 0
  fi
elif command -v nc >/dev/null 2>&1; then
  if nc -z 127.0.0.1 18789 2>/dev/null; then
    echo "$(date -Iseconds) OK" >> "$LOG"
    exit 0
  fi
else
  # Fallback: service active and port in /proc
  if systemctl --user is-active openclaw-gateway >/dev/null 2>&1; then
    echo "$(date -Iseconds) OK (service active)" >> "$LOG"
    exit 0
  fi
fi

echo "$(date -Iseconds) NOT_LISTENING restarting openclaw-gateway" >> "$LOG"
systemctl --user restart openclaw-gateway.service
exit 0
