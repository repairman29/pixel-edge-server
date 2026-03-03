#!/bin/bash
# Run inside the Pixel Debian VM. Sends a prompt to the Android host for NPU inference.
# Prereqs: Host runs an inference service reachable via ADB; VM has adb and can connect to host.
# Usage: ./npu-bridge.sh "Your prompt here"
# Set ADB_HOST to the host's address (e.g. 10.0.2.2 or the IP where host exposes ADB).

ADB_HOST="${ADB_HOST:-127.0.0.1}"
ADB_PORT="${ADB_PORT:-5555}"
PROMPT="${*:-Hello, generate a short response.}"

# Connect to host if not already connected
adb connect "${ADB_HOST}:${ADB_PORT}" 2>/dev/null || true

# Example: if the host has an app that reads prompt from stdin and prints to stdout:
# adb shell "am start -n com.example.inference/.MainActivity --es prompt \"$PROMPT\""
# Or call a localhost API on the host (if VM can reach host's network):
# curl -s -X POST "http://${ADB_HOST}:8080/complete" -d "{\"prompt\":\"$PROMPT\"}"

# Placeholder: echo that host inference is not configured; user must implement host side
echo "NPU bridge: host inference not configured. Install MediaPipe LLM Inference on the Android host and expose it (e.g. via adb shell or local API). Then edit this script to call it." >&2
echo "Prompt was: $PROMPT"
exit 1