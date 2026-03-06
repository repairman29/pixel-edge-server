#!/usr/bin/env bash
# setup-claude-heartbeat.sh — Deploy AI heartbeat as a systemd timer on the Pixel VM
#
# Requires Claude Gateway to already be running (setup-claude-gateway-daemon.sh).
# Usage: ./scripts/setup-claude-heartbeat.sh [user@host]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Claude Heartbeat — Install to Pixel VM"

# ── Copy the heartbeat script ──────────────────────────────────────────────────
echo "==> [1/4] Copying claude-heartbeat.sh to VM..."
vm_scp scripts/claude-heartbeat.sh "~/claude-gateway/claude-heartbeat.sh"
vm_ssh "chmod +x ~/claude-gateway/claude-heartbeat.sh"

# ── Ensure jq is installed (needed for JSON parsing in the script) ─────────────
echo "==> [2/4] Ensuring jq is installed..."
vm_ssh "which jq > /dev/null 2>&1 || sudo apt-get install -y jq"

# ── Install systemd timer (every 30 minutes) ──────────────────────────────────
echo "==> [3/4] Installing systemd user timer (every 30 min)..."

vm_ssh_heredoc <<'REMOTE'
set -euo pipefail
mkdir -p ~/.config/systemd/user

# Remove old cron entry if present (migrating to systemd timer)
(crontab -l 2>/dev/null | grep -v "claude-heartbeat") | crontab - 2>/dev/null || true

# Service unit (oneshot)
cat > ~/.config/systemd/user/claude-heartbeat.service <<'EOF'
[Unit]
Description=Claude AI heartbeat — autonomous health check + remediation
After=network.target claude-gateway.service

[Service]
Type=oneshot
ExecStart=/bin/bash %h/claude-gateway/claude-heartbeat.sh
StandardOutput=append:%h/claude-gateway/heartbeat-cron.log
StandardError=append:%h/claude-gateway/heartbeat-cron.log
TimeoutStartSec=180
EOF

# Timer unit — every 30 minutes, persistent across boots
cat > ~/.config/systemd/user/claude-heartbeat.timer <<'EOF'
[Unit]
Description=Claude AI heartbeat — every 30 min

[Timer]
OnBootSec=10min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable claude-heartbeat.timer
systemctl --user restart claude-heartbeat.timer

echo "  claude-heartbeat.timer installed and started."
systemctl --user list-timers claude-heartbeat.timer --no-pager 2>/dev/null || true
REMOTE

# ── Run a one-shot test ────────────────────────────────────────────────────────
echo ""
echo "==> [4/4] Running a one-shot heartbeat (this takes ~60 s for Claude to analyze)..."
vm_ssh "bash ~/claude-gateway/claude-heartbeat.sh" || {
  echo "  (heartbeat errored — check ~/claude-gateway/heartbeat.log on the VM)"
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      Claude Heartbeat deployed               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Timer:   every 30 min (systemd timer, persistent)"
echo "  Log:     ~/claude-gateway/heartbeat.log"
echo ""
echo "  View:    ssh -p ${VM_PORT} ${VM_HOST} 'tail -50 ~/claude-gateway/heartbeat.log'"
echo "  Manual:  ssh -p ${VM_PORT} ${VM_HOST} 'bash ~/claude-gateway/claude-heartbeat.sh'"
echo "  Verify:  ssh -p ${VM_PORT} ${VM_HOST} 'systemctl --user list-timers claude-heartbeat.timer'"
