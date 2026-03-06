#!/usr/bin/env bash
# setup-watchdog.sh — Deploy the 2-minute watchdog to the Pixel VM
#
# The watchdog is a fast, AI-free port monitor that restarts dead services
# immediately (no waiting for the AI heartbeat or orchestrator).
#
# It supersedes the old gateway-healthcheck timer (which only watched port 18789).
# Run this script once from your Mac to deploy it.
#
# Usage:
#   bash scripts/setup-watchdog.sh
#   PIXEL_HOST=droid@10.1.10.29 bash scripts/setup-watchdog.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Watchdog setup — Pixel VM"

# ── Deploy script ─────────────────────────────────────────────────────────────
echo "==> [1/3] Deploying watchdog.sh to VM ~/bin/..."
vm_ssh mkdir -p ~/bin
vm_scp "${SCRIPT_DIR}/watchdog.sh" "~/bin/watchdog.sh"
vm_ssh chmod +x ~/bin/watchdog.sh

# ── Install systemd timer (every 2 minutes) ───────────────────────────────────
echo "==> [2/3] Installing systemd user timer (every 2 min)..."

vm_ssh_heredoc <<'REMOTE'
set -euo pipefail
mkdir -p ~/.config/systemd/user

# Service unit (oneshot — run the script and exit)
cat > ~/.config/systemd/user/watchdog.service <<'EOF'
[Unit]
Description=Pixel edge server — fast service watchdog
After=network.target

[Service]
Type=oneshot
ExecStart=%h/bin/watchdog.sh
StandardOutput=append:%h/watchdog/watchdog.log
StandardError=append:%h/watchdog/watchdog.log
EOF

# Timer unit — runs every 2 minutes, persists across boots
cat > ~/.config/systemd/user/watchdog.timer <<'EOF'
[Unit]
Description=Pixel edge server — watchdog timer (every 2 min)

[Timer]
OnBootSec=60
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable watchdog.timer
systemctl --user restart watchdog.timer

echo "  watchdog.timer installed and started."
systemctl --user list-timers watchdog.timer --no-pager 2>/dev/null || true
REMOTE

# ── Optional: disable the old gateway-healthcheck timer ──────────────────────
echo "==> [3/3] Checking for old gateway-healthcheck timer..."

vm_ssh_heredoc <<'REMOTE'
if systemctl --user is-enabled gateway-healthcheck.timer &>/dev/null; then
  echo "  Disabling old gateway-healthcheck.timer (superseded by watchdog)..."
  systemctl --user disable --now gateway-healthcheck.timer 2>/dev/null || true
  echo "  Done. watchdog now handles all port checks including 18789."
else
  echo "  No old gateway-healthcheck.timer found — nothing to disable."
fi
REMOTE

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      Watchdog deployed                       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Checks every:  2 minutes (systemd timer, persistent)"
echo "  Watches:       claude-gateway (3456), openclaw-gateway (18789),"
echo "                 llama-server (8080 if installed), ollama + jellyfin (if Docker)"
echo "  Log:           ~/watchdog/watchdog.log"
echo ""
echo "  Verify:"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'systemctl --user list-timers watchdog.timer'"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'tail -20 ~/watchdog/watchdog.log'"
