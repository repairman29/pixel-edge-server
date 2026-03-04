#!/usr/bin/env bash
# One-shot: add npu-bridge provider to OpenClaw config on your Mac and print next steps.
# Run after: adb forward tcp:9090 tcp:9090 and ./scripts/run-npu-shim-on-mac.sh (in another terminal).

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/.."
python3 "$DIR/add-npu-provider-openclaw-mac.py"
echo ""
echo "Next: start the shim if not already running: ./scripts/run-npu-shim-on-mac.sh"
echo "Then in OpenClaw Mission Control, choose model 'Pixel NPU (host)'."
