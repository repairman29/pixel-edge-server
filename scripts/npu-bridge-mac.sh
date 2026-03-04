#!/usr/bin/env bash
# Run on your Mac. Sends a prompt to the Android NPU app via adb forward.
# Prerequisite: adb forward tcp:9090 tcp:9090 (and LLM Inference app on chat screen).
# Usage: ./npu-bridge-mac.sh "Your prompt here"

set -e
PROMPT="${*:-Hello, generate a short response.}"

# Escape for JSON: backslash and double-quote
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
PROMPT_JSON="$(json_escape "$PROMPT")"

resp=$(curl -sS -X POST http://127.0.0.1:9090/infer \
  -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"$PROMPT_JSON\"}" 2>/dev/null)

if [ -z "$resp" ]; then
  echo "NPU bridge: no response. Run: adb forward tcp:9090 tcp:9090 and keep the LLM Inference app on the chat screen." >&2
  exit 1
fi

if echo "$resp" | grep -q '"text"'; then
  echo "$resp" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g'
  exit 0
fi
echo "$resp" >&2
exit 1
