#!/usr/bin/env bash
# setup-claude-gateway.sh — Deploy the Claude Gateway to the Pixel 8 Pro VM
#
# Usage (from Mac, in the project root):
#   ./scripts/setup-claude-gateway.sh [user@host]
#
# Default target: droid@100.78.73.64 via Tailscale
# Pass droid@127.0.0.1 for USB (requires adb forward tcp:8022 tcp:8022 first).

set -euo pipefail

VM_HOST="${1:-droid@100.78.73.64}"
VM_SSH="ssh -p 8022 ${VM_HOST}"
VM_SCP="scp -P 8022"

echo "╔══════════════════════════════════════════╗"
echo "║  Claude Gateway — Deploy to Pixel VM     ║"
echo "╚══════════════════════════════════════════╝"
echo "Target: ${VM_HOST}"
echo ""

# ── 1. Confirm ANTHROPIC_API_KEY is available ──────────────────────────────────
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "⚠  ANTHROPIC_API_KEY is not set in your local environment."
  echo "   You'll need to set it in ~/.config/claude-gateway/.env on the VM."
  echo ""
fi

# ── 2. Create directory structure in the VM ───────────────────────────────────
echo "→ Creating ~/claude-gateway on the VM..."
$VM_SSH "mkdir -p ~/claude-gateway ~/.config/claude-gateway"

# ── 3. Copy source files to the VM ────────────────────────────────────────────
echo "→ Copying server files..."
$VM_SCP claude-gateway/package.json "${VM_HOST}:~/claude-gateway/package.json"
$VM_SCP claude-gateway/server.js    "${VM_HOST}:~/claude-gateway/server.js"

# ── 4. Write .env file on the VM ──────────────────────────────────────────────
echo "→ Writing .env..."
$VM_SSH "cat > ~/.config/claude-gateway/.env" << EOF
# Claude Gateway environment
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-REPLACE_ME}
CLAUDE_GATEWAY_PORT=3456
CLAUDE_MODEL=claude-opus-4-6
EOF

# ── 5. Install dependencies in the VM ─────────────────────────────────────────
echo "→ Installing npm dependencies in the VM (this takes ~30 s on first run)..."
$VM_SSH "cd ~/claude-gateway && npm install --omit=dev"

# ── 6. Quick smoke-test ────────────────────────────────────────────────────────
echo ""
echo "→ Starting gateway for a quick test (Ctrl-C to stop, then run daemon setup)..."
echo "   Or open a second terminal and run:"
echo "   curl http://100.78.73.64:3456/health"
echo ""

$VM_SSH "cd ~/claude-gateway && \
  export \$(cat ~/.config/claude-gateway/.env | grep -v '^#' | xargs) && \
  node server.js"
