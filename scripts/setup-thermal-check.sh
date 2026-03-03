#!/usr/bin/env bash
# Deploy thermal-check.sh to the Pixel VM and optionally add a cron job.
# Run from your Mac. Usage: ./scripts/setup-thermal-check.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying thermal check to ${TARGET} ==="

# Read the thermal script and deploy via SSH
thermal_script=$(cat "$SCRIPT_DIR/thermal-check.sh")
ssh $SSH_OPTS "$TARGET" "mkdir -p ~/bin && cat > ~/bin/thermal-check.sh && chmod +x ~/bin/thermal-check.sh" <<< "$thermal_script"

# Optional: add cron job (every 5 minutes). User can remove or edit with crontab -e.
ssh $SSH_OPTS "$TARGET" bash -s << 'REMOTE'
(crontab -l 2>/dev/null | grep -v thermal-check.sh; echo "*/5 * * * * $HOME/bin/thermal-check.sh") | crontab - 2>/dev/null || true
echo "Cron updated (every 5 min). Check logs: tail -f /tmp/thermal-check.log"
REMOTE

echo ""
echo "Thermal check installed at ~/bin/thermal-check.sh in the VM."
echo "To run manually: ssh -p 8022 $TARGET '~/bin/thermal-check.sh'"
echo "To adjust threshold (default 40C): THRESHOLD_MC=45000 ~/bin/thermal-check.sh"
