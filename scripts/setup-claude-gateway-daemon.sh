#!/usr/bin/env bash
# setup-claude-gateway-daemon.sh — Install Claude Gateway as a systemd user service
#
# Run AFTER setup-claude-gateway.sh.
# Usage: ./scripts/setup-claude-gateway-daemon.sh [user@host]

set -euo pipefail

VM_HOST="${1:-droid@100.78.73.64}"
VM_SSH="ssh -p 8022 ${VM_HOST}"

echo "╔══════════════════════════════════════════╗"
echo "║  Claude Gateway — Install systemd daemon ║"
echo "╚══════════════════════════════════════════╝"
echo "Target: ${VM_HOST}"
echo ""

# ── Write the systemd unit ────────────────────────────────────────────────────
echo "→ Writing ~/.config/systemd/user/claude-gateway.service..."
$VM_SSH "mkdir -p ~/.config/systemd/user && cat > ~/.config/systemd/user/claude-gateway.service" << 'UNIT'
[Unit]
Description=Claude Gateway — OpenAI-compatible Claude API for Pixel AI Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/claude-gateway
EnvironmentFile=%h/.config/claude-gateway/.env
ExecStart=/bin/bash -c 'source ~/.nvm/nvm.sh && node server.js'
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNIT

# ── Enable & (re)start ────────────────────────────────────────────────────────
echo "→ Enabling and starting claude-gateway.service..."
$VM_SSH "
  export XDG_RUNTIME_DIR=/run/user/\$(id -u)
  systemctl --user daemon-reload
  systemctl --user enable claude-gateway
  systemctl --user restart claude-gateway
  sleep 2
  systemctl --user status claude-gateway --no-pager
"

# ── Show access info ──────────────────────────────────────────────────────────
echo ""
echo "✓ Claude Gateway is running as a persistent systemd user service."
echo ""
echo "  Check status:  ssh -p 8022 ${VM_HOST} 'systemctl --user status claude-gateway'"
echo "  View logs:     ssh -p 8022 ${VM_HOST} 'journalctl --user -u claude-gateway -f'"
echo "  Stop:          ssh -p 8022 ${VM_HOST} 'systemctl --user stop claude-gateway'"
echo ""
echo "  Health check (via Tailscale): curl http://100.78.73.64:3456/health"
echo ""
echo "  OpenAI-compatible endpoint:"
echo "    export OPENAI_BASE_URL=http://100.78.73.64:3456/v1"
echo "    export OPENAI_API_KEY=dummy   # gateway uses its own ANTHROPIC_API_KEY"
echo ""
echo "  Agentic task example:"
echo "    curl -s -X POST http://100.78.73.64:3456/v1/agent \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"task\": \"Check thermal temps, disk usage, and list open ports. Summarize the Pixel server health.\"}'"
