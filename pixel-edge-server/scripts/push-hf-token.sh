#!/usr/bin/env bash
# Push HF token to the Pixel so the gateway can use it. Token is read from scripts/.hf-token (gitignored).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_FILE="$SCRIPT_DIR/.hf-token"
if [ ! -f "$TOKEN_FILE" ]; then
  echo "Create $TOKEN_FILE with your Hugging Face token (one line), or pass token as first argument."
  if [ -n "$1" ]; then
    echo "$1" > "$TOKEN_FILE"
    echo "Wrote token to $TOKEN_FILE"
  else
    exit 1
  fi
fi
TOKEN=$(cat "$TOKEN_FILE" | tr -d '\r\n')
TMP="/tmp/env.pixel-agent.$$"
echo "export HF_TOKEN=$TOKEN" > "$TMP"
adb push "$TMP" /sdcard/jarvis/.env.pixel-agent
rm -f "$TMP"
echo "Pushed. In Termux run: cp /sdcard/jarvis/.env.pixel-agent ~/.env.pixel-agent"
echo "Then run the gateway with: ~/run-gateway.sh  (or: source ~/.env.pixel-agent && ./pixel-agent-v2)"
