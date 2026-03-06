#!/usr/bin/env bash
# setup-openclaw-orchestrator.sh — Deploy the OpenClaw orchestrator to the Pixel VM
#
# The orchestrator is the "OpenClaw calling the shots" loop:
#   - Runs every 10 minutes via systemd timer
#   - Dispatches a full management task to Claude Gateway's /v1/agent endpoint
#   - Claude checks every service, fixes anything broken, monitors resources,
#     rotates logs, and writes ~/openclaw-orchestrator/status.md
#
# Prerequisites:
#   - Claude Gateway must be running (setup-claude-gateway-daemon.sh)
#   - ANTHROPIC_API_KEY must be in ~/.config/claude-gateway/.env on VM
#
# Usage:
#   bash scripts/setup-openclaw-orchestrator.sh
#   PIXEL_HOST=droid@10.1.10.29 bash scripts/setup-openclaw-orchestrator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "OpenClaw Orchestrator — setup"

# ── Deploy orchestrator script ────────────────────────────────────────────────
echo "==> [1/3] Deploying openclaw-orchestrator.sh to VM ~/bin/..."
vm_ssh "mkdir -p ~/bin ~/openclaw-orchestrator"
vm_scp "${SCRIPT_DIR}/openclaw-orchestrator.sh" "~/bin/openclaw-orchestrator.sh"
vm_ssh chmod +x ~/bin/openclaw-orchestrator.sh

# ── Install systemd service + timer ───────────────────────────────────────────
echo "==> [2/3] Installing systemd user timer (every 10 min)..."

vm_ssh_heredoc <<'REMOTE'
set -euo pipefail
mkdir -p ~/.config/systemd/user

# Service unit
cat > ~/.config/systemd/user/openclaw-orchestrator.service <<'EOF'
[Unit]
Description=OpenClaw agentic system orchestrator
After=network.target claude-gateway.service

[Service]
Type=oneshot
ExecStart=%h/bin/openclaw-orchestrator.sh
StandardOutput=append:%h/openclaw-orchestrator/orchestrator.log
StandardError=append:%h/openclaw-orchestrator/orchestrator.log
TimeoutStartSec=200
EOF

# Timer unit — every 10 minutes, offset by 5 min from boot to let services settle
cat > ~/.config/systemd/user/openclaw-orchestrator.timer <<'EOF'
[Unit]
Description=OpenClaw agentic orchestrator — every 10 min

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable openclaw-orchestrator.timer
systemctl --user restart openclaw-orchestrator.timer

echo "  openclaw-orchestrator.timer installed and started."
systemctl --user list-timers openclaw-orchestrator.timer --no-pager 2>/dev/null || true
REMOTE

# ── Run a one-shot test ───────────────────────────────────────────────────────
echo ""
echo "==> [3/3] Running first orchestrator cycle (this takes up to ~3 min)..."
echo "  (Claude will check all services, fix any issues, write status.md)"
echo ""

vm_ssh_heredoc <<'REMOTE'
set -euo pipefail
if ! curl -sf http://127.0.0.1:3456/health >/dev/null 2>&1; then
  echo "  WARN: Claude Gateway not reachable — skipping test run."
  echo "  Start the gateway first: systemctl --user start claude-gateway"
  exit 0
fi
echo "  Gateway is up — dispatching test task..."
~/bin/openclaw-orchestrator.sh
echo ""
echo "  ── Status file ──────────────────────────────"
cat ~/openclaw-orchestrator/status.md 2>/dev/null || echo "  (status.md not created yet)"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   OpenClaw Orchestrator deployed             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Runs every:  10 minutes (systemd timer, persistent)"
echo "  Does:        check all services, restart failures, monitor resources,"
echo "               rotate logs, write structured status.md"
echo ""
echo "  Key files on VM:"
echo "    ~/openclaw-orchestrator/status.md   ← current system state"
echo "    ~/openclaw-orchestrator/orchestrator.log ← run history"
echo ""
echo "  Check status from Mac:"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'cat ~/openclaw-orchestrator/status.md'"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'tail -30 ~/openclaw-orchestrator/orchestrator.log'"
