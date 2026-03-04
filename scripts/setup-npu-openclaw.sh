#!/usr/bin/env bash
# Deploy NPU bridge + OpenClaw shim and add npu-bridge provider. Run after the Android host app is serving on 9090.
# Run from your Mac. Usage: ./scripts/setup-npu-openclaw.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
SCP_OPTS="-P 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NPU_SHIM_PORT="${NPU_SHIM_PORT:-9190}"

echo "=== Deploying NPU bridge + OpenClaw shim to ${TARGET} ==="

scp $SCP_OPTS "$DIR/npu-bridge.sh" "$TARGET:~/bin/npu-bridge.sh"
scp $SCP_OPTS "$DIR/npu-openclaw-shim.py" "$TARGET:~/bin/npu-openclaw-shim.py"

ssh $SSH_OPTS "$TARGET" bash -s << REMOTE
set -e
chmod +x ~/bin/npu-bridge.sh ~/bin/npu-openclaw-shim.py
mkdir -p ~/.config/systemd/user

# Systemd user service for the shim (OpenAI-compatible endpoint for OpenClaw)
cat > ~/.config/systemd/user/npu-openclaw-shim.service << 'SVC'
[Unit]
Description=NPU OpenClaw shim (OpenAI-compatible endpoint for npu-bridge)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 %h/bin/npu-openclaw-shim.py
Environment=NPU_SHIM_PORT=$NPU_SHIM_PORT
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
SVC

systemctl --user daemon-reload
systemctl --user enable npu-openclaw-shim.service
systemctl --user restart npu-openclaw-shim.service
sleep 1
systemctl --user is-active npu-openclaw-shim.service
REMOTE

# Add npu-bridge provider to openclaw.json (merge into existing models.providers)
ssh $SSH_OPTS "$TARGET" python3 - << PY
import json
path = "/home/droid/.openclaw/openclaw.json"
with open(path) as f:
    data = json.load(f)
providers = data.setdefault("models", {}).setdefault("providers", {})
if "npu-bridge" not in providers:
    providers["npu-bridge"] = {
        "baseUrl": "http://127.0.0.1:$NPU_SHIM_PORT",
        "api": "openai-completions",
        "models": [
            {
                "id": "pixel-npu",
                "name": "Pixel NPU (host)",
                "contextWindow": 4096,
                "maxTokens": 512,
                "reasoning": False,
                "input": ["text"],
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
            }
        ]
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("Added npu-bridge provider.")
else:
    print("npu-bridge provider already present.")
PY

ssh $SSH_OPTS "$TARGET" "systemctl --user restart openclaw-gateway; sleep 2; systemctl --user is-active openclaw-gateway"

echo ""
echo "NPU OpenClaw shim is running at http://127.0.0.1:$NPU_SHIM_PORT"
echo "Model id: npu-bridge/pixel-npu"
echo "In Mission Control you can switch the default model to 'Pixel NPU (host)' to use the NPU."
echo "Ensure the Android app (HttpLlmServer on port 9090) is running on the Pixel before using this model."