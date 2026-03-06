#!/usr/bin/env bash
# Deploy thermal-check.sh to the Pixel VM as a systemd timer.
# Run from your Mac. Usage: ./scripts/setup-thermal-check.sh [droid@100.78.73.64]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Thermal check — deploy"

echo "==> [1/2] Deploying thermal-check.sh to VM..."
vm_ssh "mkdir -p ~/bin"
vm_scp "${SCRIPT_DIR}/thermal-check.sh" "~/bin/thermal-check.sh"
vm_ssh "chmod +x ~/bin/thermal-check.sh"

echo "==> [2/2] Installing systemd timer (every 5 min)..."

vm_ssh_heredoc << 'REMOTE'
set -e
mkdir -p ~/.config/systemd/user

# Remove old cron entry if present (migrating to systemd timer)
(crontab -l 2>/dev/null | grep -v thermal-check.sh) | crontab - 2>/dev/null || true

# Service unit (oneshot)
cat > ~/.config/systemd/user/thermal-check.service <<'EOF'
[Unit]
Description=Pixel thermal zone check

[Service]
Type=oneshot
ExecStart=%h/bin/thermal-check.sh
EOF

# Timer unit — every 5 minutes
cat > ~/.config/systemd/user/thermal-check.timer <<'EOF'
[Unit]
Description=Pixel thermal check — every 5 min

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable thermal-check.timer
systemctl --user restart thermal-check.timer

echo "  thermal-check.timer installed and started."
systemctl --user list-timers thermal-check.timer --no-pager 2>/dev/null || true
REMOTE

echo ""
echo "Thermal check installed at ~/bin/thermal-check.sh in the VM."
echo "  Timer:   every 5 min (systemd timer, persistent)"
echo "  Log:     /tmp/thermal-check.log"
echo "  Manual:  ssh -p ${VM_PORT} ${VM_HOST} '~/bin/thermal-check.sh'"
echo "  Verify:  ssh -p ${VM_PORT} ${VM_HOST} 'systemctl --user list-timers thermal-check.timer'"
echo "  Adjust:  THRESHOLD_MC=45000 ~/bin/thermal-check.sh (default 40°C)"
