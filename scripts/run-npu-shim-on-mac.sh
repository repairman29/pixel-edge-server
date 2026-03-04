#!/usr/bin/env bash
# Run the NPU OpenClaw shim on your Mac (no VM needed).
# Use this when the Pixel VM/terminal isn't available.
#
# Before running:
#   1. adb forward tcp:9090 tcp:9090
#   2. Open the LLM Inference app on the Pixel and go to the chat screen.
#
# Then run this script. It starts the shim on http://127.0.0.1:9190.
# Point OpenClaw (on your Mac) at baseUrl http://127.0.0.1:9190, model pixel-npu.

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NPU_BRIDGE="$DIR/npu-bridge-mac.sh"
export NPU_SHIM_PORT="${NPU_SHIM_PORT:-9190}"
chmod +x "$DIR/npu-bridge-mac.sh" 2>/dev/null || true

echo "NPU shim on Mac: http://127.0.0.1:$NPU_SHIM_PORT"
echo "Bridge: $NPU_BRIDGE (uses adb forward 9090)"
echo "Press Ctrl+C to stop."
exec python3 "$DIR/npu-openclaw-shim.py"
