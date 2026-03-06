#!/usr/bin/env bash
# setup-claude-heartbeat.sh — Deploy AI heartbeat cron to the Pixel VM
#
# Requires Claude Gateway to already be running (setup-claude-gateway-daemon.sh).
# Usage: ./scripts/setup-claude-heartbeat.sh [user@host]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Claude Heartbeat — Install to Pixel VM"

# ── Copy the heartbeat script ──────────────────────────────────────────────────
echo "→ Copying claude-heartbeat.sh to VM..."
vm_scp scripts/claude-heartbeat.sh "~/claude-gateway/claude-heartbeat.sh"
vm_ssh "chmod +x ~/claude-gateway/claude-heartbeat.sh"

# ── Ensure jq is installed (needed for JSON parsing in the script) ─────────────
echo "→ Ensuring jq is installed..."
vm_ssh "which jq > /dev/null 2>&1 || sudo apt-get install -y jq"

# ── Install cron job (every 30 minutes) ───────────────────────────────────────
echo "→ Installing cron job (every 30 minutes)..."
vm_ssh '
  # Remove any existing claude-heartbeat cron entries
  (crontab -l 2>/dev/null | grep -v "claude-heartbeat") | crontab -

  # Add new entry: run at :00 and :30 of every hour
  (crontab -l 2>/dev/null; echo "0,30 * * * * bash ~/claude-gateway/claude-heartbeat.sh >> ~/claude-gateway/heartbeat-cron.log 2>&1") | crontab -

  echo "Cron installed:"
  crontab -l | grep claude
'

# ── Run a one-shot test ────────────────────────────────────────────────────────
echo ""
echo "→ Running a one-shot heartbeat (this takes ~60 s for Claude to analyze)..."
vm_ssh "source ~/.config/claude-gateway/.env 2>/dev/null; bash ~/claude-gateway/claude-heartbeat.sh" || {
  echo "  (heartbeat errored — check ~/claude-gateway/heartbeat.log on the VM)"
}

echo ""
echo "✓ Claude Heartbeat installed."
echo ""
echo "  View latest report:  ssh -p ${VM_PORT} ${VM_HOST} 'tail -50 ~/claude-gateway/heartbeat.log'"
echo "  Run manually:        ssh -p ${VM_PORT} ${VM_HOST} 'bash ~/claude-gateway/claude-heartbeat.sh'"
echo "  Cron schedule:       every 30 min (:00 and :30)"
