#!/usr/bin/env bash
# setup-claude-gateway.sh — Deploy the Claude Gateway to the Pixel 8 Pro VM
#
# Usage (from Mac, in the project root):
#   ./scripts/setup-claude-gateway.sh [user@host]
#
# Default target: droid@100.78.73.64 via Tailscale
# Pass droid@127.0.0.1 for USB (requires adb forward tcp:8022 tcp:8022 first).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Claude Gateway — Deploy to Pixel VM"

# ── 1. Confirm ANTHROPIC_API_KEY is available ──────────────────────────────────
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo ""
  echo "ERROR: ANTHROPIC_API_KEY is not set."
  echo ""
  echo "  export ANTHROPIC_API_KEY=sk-ant-..."
  echo "  bash scripts/setup-claude-gateway.sh"
  echo ""
  exit 1
fi
if [[ "${ANTHROPIC_API_KEY}" == "REPLACE_ME" ]]; then
  echo ""
  echo "ERROR: ANTHROPIC_API_KEY is still set to the placeholder 'REPLACE_ME'."
  echo "  Set it to a real key before deploying."
  echo ""
  exit 1
fi

# ── 2. Create directory structure in the VM ───────────────────────────────────
echo "→ Creating ~/claude-gateway on the VM..."
vm_ssh "mkdir -p ~/claude-gateway ~/.config/claude-gateway"

# ── 3. Copy source files to the VM ────────────────────────────────────────────
echo "→ Copying server files..."
vm_scp claude-gateway/package.json "~/claude-gateway/package.json"
vm_scp claude-gateway/server.js    "~/claude-gateway/server.js"

# ── 4. Write .env file on the VM ──────────────────────────────────────────────
echo "→ Writing .env..."
vm_ssh "cat > ~/.config/claude-gateway/.env" << EOF
# Claude Gateway environment
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-REPLACE_ME}
CLAUDE_GATEWAY_PORT=3456
CLAUDE_MODEL=claude-opus-4-6
EOF

# ── 5. Install dependencies in the VM ─────────────────────────────────────────
echo "→ Installing npm dependencies in the VM (this takes ~30 s on first run)..."
vm_ssh "cd ~/claude-gateway && npm install --omit=dev"

# ── 6. Quick smoke-test ────────────────────────────────────────────────────────
echo ""
echo "→ Starting gateway for a quick test (Ctrl-C to stop, then run daemon setup)..."
echo "   Or open a second terminal and run:"
echo "   curl http://100.78.73.64:3456/health"
echo ""

vm_ssh "cd ~/claude-gateway && \
  export \$(cat ~/.config/claude-gateway/.env | grep -v '^#' | xargs) && \
  node server.js"
