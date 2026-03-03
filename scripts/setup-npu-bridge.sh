#!/usr/bin/env bash
# Deploy npu-bridge.sh to the VM. You still need to set up the Android host inference app.
# Run from your Mac. Usage: ./scripts/setup-npu-bridge.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying NPU bridge script to ${TARGET} ==="
bridge=$(cat "$SCRIPT_DIR/npu-bridge.sh")
ssh $SSH_OPTS "$TARGET" "mkdir -p ~/bin && cat > ~/bin/npu-bridge.sh && chmod +x ~/bin/npu-bridge.sh" <<< "$bridge"
echo "Installed ~/bin/npu-bridge.sh. Install ADB in VM if needed: sudo apt install -y android-tools-adb"
echo "See docs/hybrid-npu-inference.md for host setup (MediaPipe LLM Inference, ADB listener)."