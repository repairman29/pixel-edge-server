#!/usr/bin/env bash
# One-shot NPU setup on your Mac (no VM needed).
# Does: adb forward, add OpenClaw provider, start the shim in the background.
# Run from: ~/Projects (with Pixel connected via USB).
#
# After this runs, you do:
#   1. Open the LLM Inference app on the Pixel and go to the chat screen.
#   2. In OpenClaw Mission Control, select model "Pixel NPU (host)".

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== NPU setup (Mac) ==="

# 1. Forward Android app port to Mac
echo "1. adb forward 9090..."
adb forward tcp:9090 tcp:9090 2>/dev/null || true

# 2. Add npu-bridge provider to OpenClaw config
echo "2. OpenClaw config..."
python3 "$DIR/add-npu-provider-openclaw-mac.py"

# 3. Start shim in background (so it keeps running)
echo "3. Starting NPU shim on port 9190 (background)..."
export NPU_BRIDGE="$DIR/npu-bridge-mac.sh"
export NPU_SHIM_PORT="${NPU_SHIM_PORT:-9190}"
chmod +x "$DIR/npu-bridge-mac.sh" 2>/dev/null || true
nohup python3 "$DIR/npu-openclaw-shim.py" </dev/null >> "$PROJECT_DIR/npu-shim.log" 2>&1 &
SHIM_PID=$!
sleep 1
if kill -0 $SHIM_PID 2>/dev/null; then
  echo "   Shim running (PID $SHIM_PID). Log: $PROJECT_DIR/npu-shim.log"
else
  echo "   Shim may have exited; check npu-shim.log"
fi

echo ""
echo "=== Done ==="
echo "You do:"
echo "  1. On the Pixel: open LLM Inference app → chat screen (model loaded)."
echo "  2. In OpenClaw: Mission Control → select model 'Pixel NPU (host)'."
echo ""
echo "To stop the shim later: kill $SHIM_PID   (or: pkill -f npu-openclaw-shim)"
