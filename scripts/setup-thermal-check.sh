#!/usr/bin/env bash
# Deploy thermal-check.sh to the Pixel VM and optionally add a cron job.
# Run from your Mac. Usage: ./scripts/setup-thermal-check.sh [droid@100.78.73.64]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "Thermal check — deploy"

vm_scp "${SCRIPT_DIR}/thermal-check.sh" "~/bin/thermal-check.sh"
vm_ssh "mkdir -p ~/bin && chmod +x ~/bin/thermal-check.sh"

# Optional: add cron job (every 5 minutes). User can remove or edit with crontab -e.
vm_ssh_heredoc << 'REMOTE'
(crontab -l 2>/dev/null | grep -v thermal-check.sh; echo "*/5 * * * * $HOME/bin/thermal-check.sh") | crontab - 2>/dev/null || true
echo "Cron updated (every 5 min). Check logs: tail -f /tmp/thermal-check.log"
REMOTE

echo ""
echo "Thermal check installed at ~/bin/thermal-check.sh in the VM."
echo "To run manually: ssh -p ${VM_PORT} ${VM_HOST} '~/bin/thermal-check.sh'"
echo "To adjust threshold (default 40C): THRESHOLD_MC=45000 ~/bin/thermal-check.sh"
