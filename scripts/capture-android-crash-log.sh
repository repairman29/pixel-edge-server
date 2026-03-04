#!/usr/bin/env bash
# Capture Android app crash logs. Run right after the app crashes.
# Usage: ./scripts/capture-android-crash-log.sh [output_file]

set -e
OUT="${1:-./android-crash-log.txt}"
echo "Capturing last 200 lines of logcat (AndroidRuntime, llminference, NanoHTTPD)..."
adb logcat -d -t 200 | grep -E "AndroidRuntime|FATAL|llminference|NanoHTTPD|HttpLlmServer|NpuInference|Exception|Error" > "$OUT" 2>/dev/null || adb logcat -d -t 300 > "$OUT"
echo "Written to $OUT"
echo "--- Last 40 lines ---"
tail -40 "$OUT"
