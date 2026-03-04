#!/bin/bash
# Run inside the Pixel Debian VM. Sends a prompt to the Android host NPU app via adb shell curl.
# Host app must listen on http://127.0.0.1:9090/infer (POST JSON {"prompt":"..."}).
# Usage: ./npu-bridge.sh "Your prompt here"
# Set ADB_HOST and ADB_PORT if the host is not at 127.0.0.1:5555.

ADB_HOST="${ADB_HOST:-127.0.0.1}"
ADB_PORT="${ADB_PORT:-5555}"
PROMPT="${*:-Hello, generate a short response.}"

# Connect to host if not already (USB: adb forward from Mac; in-VM adb may talk to host via 127.0.0.1:5555)
adb connect "${ADB_HOST}:${ADB_PORT}" 2>/dev/null || true

# Escape for JSON: backslash and double-quote
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
PROMPT_JSON="$(json_escape "$PROMPT")"

# Run curl on the HOST (Android) so 127.0.0.1:9090 is the app's server
resp=$(adb shell "curl -sS -X POST http://127.0.0.1:9090/infer -H 'Content-Type: application/json' -d '{\"prompt\":\"$PROMPT_JSON\"}'" 2>/dev/null)

if [ -z "$resp" ]; then
  echo "NPU bridge: no response. Is the Android app running with HttpLlmServer on port 9090?" >&2
  exit 1
fi

# Expect {"text":"..."} or {"error":"..."}
if echo "$resp" | grep -q '"text"'; then
  echo "$resp" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g'
  exit 0
fi
echo "$resp" >&2
exit 1
