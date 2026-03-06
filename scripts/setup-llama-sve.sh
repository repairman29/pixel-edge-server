#!/bin/bash
# setup-llama-sve.sh — Build llama.cpp with ARM SVE on the Pixel Debian VM.
#
# Compiles llama.cpp from source with GGML_SVE=ON (Tensor G3 Scalable Vector
# Extension support) and installs llama-server as a systemd user service with an
# OpenAI-compatible API on port 8080.  Optionally integrates with Claude Gateway
# by setting LOCAL_LLM_URL in the gateway .env.
#
# Run from your Mac:
#   bash scripts/setup-llama-sve.sh
#
# Environment overrides:
#   PIXEL_HOST    — SSH target  (default: droid@100.78.73.64)
#   PIXEL_PORT    — SSH port    (default: 8022)
#   MODEL_URL     — GGUF download URL (default: Llama-3.2-3B-Instruct Q4_K_M)
#   MODEL_NAME    — Local filename   (default: Llama-3.2-3B-Instruct-Q4_K_M.gguf)
#   SERVE_PORT    — llama-server port (default: 8080)
#   LINK_GATEWAY  — set to "1" to auto-configure Claude Gateway's LOCAL_LLM_URL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

MODEL_URL="${MODEL_URL:-https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf}"
MODEL_NAME="${MODEL_NAME:-Llama-3.2-3B-Instruct-Q4_K_M.gguf}"
SERVE_PORT="${SERVE_PORT:-8080}"
LINK_GATEWAY="${LINK_GATEWAY:-1}"

vm_banner "llama.cpp SVE build — Pixel Tensor G3"
echo "  Model  : ${MODEL_NAME}"
echo "  Port   : ${SERVE_PORT}"
echo ""

# ── Step 1: build llama.cpp ───────────────────────────────────────────────────
echo "==> [1/4] Building llama.cpp with GGML_SVE=ON..."

vm_ssh_heredoc <<'REMOTE'
set -euo pipefail

# Install build dependencies
echo "  Installing build deps..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  build-essential cmake git curl wget ca-certificates libcurl4-openssl-dev

# Clone or update llama.cpp
if [ -d ~/llama.cpp ]; then
  echo "  Updating existing llama.cpp clone..."
  git -C ~/llama.cpp fetch --depth=1 origin main
  git -C ~/llama.cpp reset --hard origin/main
else
  echo "  Cloning llama.cpp..."
  git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama.cpp
fi

# CMake configure with SVE + native tuning for Tensor G3 (Cortex-X3 / A715)
echo "  Configuring cmake (SVE + NATIVE)..."
cmake -B ~/llama.cpp/build ~/llama.cpp \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_SVE=ON \
  -DGGML_NATIVE=ON \
  -DLLAMA_CURL=ON \
  -DCMAKE_C_FLAGS="-march=armv9-a+sve" \
  -DCMAKE_CXX_FLAGS="-march=armv9-a+sve" \
  2>&1 | tail -8

# Build (use all cores; Pixel 8 Pro has 9 cores in Debian)
echo "  Building ($(nproc) cores)..."
cmake --build ~/llama.cpp/build --config Release -j"$(nproc)" 2>&1 | tail -5

echo "  Build complete. Binaries:"
ls ~/llama.cpp/build/bin/
REMOTE

# ── Step 2: download model ────────────────────────────────────────────────────
echo ""
echo "==> [2/4] Downloading model: ${MODEL_NAME}..."

vm_ssh_heredoc -s -- "${MODEL_URL}" "${MODEL_NAME}" <<'REMOTE'
MODEL_URL="$1"
MODEL_NAME="$2"
mkdir -p ~/llama-models
if [ -f ~/llama-models/"${MODEL_NAME}" ]; then
  echo "  Model already present, skipping download."
else
  echo "  Downloading (this may take a while on mobile data)..."
  wget -q --show-progress -O ~/llama-models/"${MODEL_NAME}" "${MODEL_URL}"
  echo "  Download complete."
fi
REMOTE

# ── Step 3: install systemd service ───────────────────────────────────────────
echo ""
echo "==> [3/4] Installing llama-server systemd service (port ${SERVE_PORT})..."

vm_ssh_heredoc -s -- "${SERVE_PORT}" "${MODEL_NAME}" <<'REMOTE'
SERVE_PORT="$1"
MODEL_NAME="$2"

mkdir -p ~/bin ~/.config/systemd/user

# Launch wrapper
cat > ~/bin/llama-serve.sh <<EOF
#!/bin/bash
# llama-server — OpenAI-compatible API (llama.cpp SVE build)
exec ~/llama.cpp/build/bin/llama-server \
  --model ~/llama-models/${MODEL_NAME} \
  --host 0.0.0.0 \
  --port ${SERVE_PORT} \
  --ctx-size 4096 \
  --n-predict 512 \
  --threads \$(nproc) \
  --log-disable
EOF
chmod +x ~/bin/llama-serve.sh

# Systemd unit
cat > ~/.config/systemd/user/llama-server.service <<EOF
[Unit]
Description=llama.cpp OpenAI-compatible server (ARM SVE — Tensor G3)
After=network.target

[Service]
Type=simple
ExecStart=/home/droid/bin/llama-serve.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:/home/droid/llama-server.log
StandardError=append:/home/droid/llama-server.log
Environment=HOME=/home/droid

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable llama-server.service
systemctl --user restart llama-server.service

echo "  Waiting for llama-server to start..."
sleep 3
systemctl --user status llama-server.service --no-pager || true
REMOTE

# ── Step 4: link to Claude Gateway ────────────────────────────────────────────
if [ "${LINK_GATEWAY}" = "1" ]; then
  echo ""
  echo "==> [4/4] Linking Claude Gateway → llama-server (LOCAL_LLM_URL)..."

  vm_ssh_heredoc -s -- "${SERVE_PORT}" <<'REMOTE'
PORT="$1"
ENV_FILE=~/.config/claude-gateway/.env
if [ ! -f "${ENV_FILE}" ]; then
  echo "  Claude Gateway .env not found at ${ENV_FILE}; skipping auto-link."
  echo "  Add manually: LOCAL_LLM_URL=http://127.0.0.1:${PORT}/v1/chat/completions"
else
  # Remove old LOCAL_LLM_URL entry if present, then append new one
  sed -i '/^LOCAL_LLM_URL=/d' "${ENV_FILE}"
  echo "LOCAL_LLM_URL=http://127.0.0.1:${PORT}/v1/chat/completions" >> "${ENV_FILE}"
  echo "  LOCAL_LLM_URL written to ${ENV_FILE}."
  echo "  Restarting claude-gateway to pick up change..."
  systemctl --user restart claude-gateway.service 2>/dev/null && echo "  claude-gateway restarted." || true
fi
REMOTE
else
  echo ""
  echo "==> [4/4] Skipping Claude Gateway link (LINK_GATEWAY != 1)."
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║    llama-server ready on Pixel VM            ║"
echo "╚══════════════════════════════════════════════╝"
echo "  Model    : ${MODEL_NAME}"
echo "  API      : http://100.78.73.64:${SERVE_PORT}/v1/chat/completions"
echo "  Model ID : 'local' or any haiku/* name routes here via Claude Gateway"
echo ""
echo "  Quick test:"
echo "  curl http://100.78.73.64:${SERVE_PORT}/v1/chat/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"local\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi!\"}],\"max_tokens\":64}'"
echo ""
echo "  Via Claude Gateway (if linked):"
echo "  curl http://100.78.73.64:3456/v1/chat/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"local\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi!\"}]}'"
echo ""
echo "  Logs: ssh -p ${VM_PORT} ${VM_HOST} 'tail -f ~/llama-server.log'"
