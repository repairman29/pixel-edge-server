#!/usr/bin/env bash
# Test the NPU bridge from your Mac. Requires: Android app running (port 9090), adb, VM reachable.
# Usage: ./scripts/test-npu-bridge.sh [droid@127.0.0.1]
# For USB: adb forward tcp:8022 tcp:8022 first, then use droid@127.0.0.1

TARGET="${1:-droid@100.78.73.64}"
SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"

echo "1. Testing host app from Mac (adb shell curl)..."
adb shell "curl -sS -X POST http://127.0.0.1:9090/infer -H 'Content-Type: application/json' -d '{\"prompt\":\"Say hello in one word.\"}'" 2>/dev/null || { echo "   Failed. Is the Android app running with HttpLlmServer on 9090?"; exit 1; }
echo ""

echo "2. Testing VM npu-bridge.sh..."
ssh $SSH_OPTS "$TARGET" '~/bin/npu-bridge.sh "Say hello in one word."' 2>/dev/null || { echo "   Failed. Is adb in the VM connected to the host? Try: adb connect 127.0.0.1:5555"; exit 1; }
echo ""

echo "3. Testing OpenClaw shim in VM (if installed)..."
ssh $SSH_OPTS "$TARGET" "curl -sS -X POST http://127.0.0.1:9190/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello.\"}]}'" 2>/dev/null | head -c 300
echo ""
echo ""
echo "Done. If step 1 and 2 pass, NPU bridge is working. Step 3 requires the shim (setup-npu-openclaw.sh)."
