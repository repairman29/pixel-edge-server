#!/usr/bin/env bash
# Forward port and test the gateway. Start the gateway in Termux first (~/run-gateway.sh).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "1. Forwarding port 18789..."
adb forward tcp:18789 tcp:18789 2>/dev/null || true

echo "2. Checking gateway (GET /health)..."
HEALTH=$(curl -s -m 5 http://127.0.0.1:18789/health 2>/dev/null || true)
if [ -n "$HEALTH" ]; then
  echo "Health: $HEALTH"
  echo "3. Testing /chat..."
  RESP=$(curl -s -m 20 -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}' 2>/dev/null || true)
  if [ -n "$RESP" ]; then
    echo "Response: $RESP"
    echo "Success: gateway is running and responded."
  else
    echo "No response from /chat (Jarvis/HF may be slow or failing)."
  fi
else
  echo "No response from gateway. In Termux run: ~/run-gateway.sh (then rebuild with latest source if you get empty /chat)."
fi
