#!/usr/bin/env bash
# Install the "Jarvis wake" HTTP server on the Pixel VM so iPhone (Tailscale) can restart the gateway.
# Run from your Mac. Usage: ./scripts/setup-jarvis-wake.sh [droid@100.78.73.64]
# Set JARVIS_WAKE_TOKEN before running to use a specific token; otherwise one is generated.

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
SCP_OPTS="-P 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"
PORT="${JARVIS_WAKE_PORT:-9180}"
DIR="$(cd "$(dirname "$0")" && pwd)"

# Generate token if not set
if [ -z "$JARVIS_WAKE_TOKEN" ]; then
  JARVIS_WAKE_TOKEN=$(openssl rand -hex 16)
  echo "Generated JARVIS_WAKE_TOKEN (save this for the iPhone Shortcut): ${JARVIS_WAKE_TOKEN}"
fi

echo "=== Installing Jarvis wake server on ${TARGET} (port ${PORT}) ==="

scp $SCP_OPTS "$DIR/jarvis-wake-server.py" "$TARGET:~/bin/jarvis-wake-server.py"

ssh $SSH_OPTS "$TARGET" bash -s << REMOTE
set -e
mkdir -p ~/bin ~/.openclaw ~/.config/systemd/user
chmod +x ~/bin/jarvis-wake-server.py
echo '$JARVIS_WAKE_TOKEN' > ~/.openclaw/wake-token
chmod 600 ~/.openclaw/wake-token

# Systemd user service
cat > ~/.config/systemd/user/jarvis-wake.service << 'SVC'
[Unit]
Description=Jarvis wake: HTTP endpoint to restart openclaw-gateway (for iPhone Shortcut)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 %h/bin/jarvis-wake-server.py
Environment=JARVIS_WAKE_PORT=$PORT
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
SVC

systemctl --user daemon-reload
systemctl --user enable jarvis-wake.service
systemctl --user restart jarvis-wake.service
sleep 1
systemctl --user is-active jarvis-wake.service
REMOTE

echo ""
echo "Jarvis wake server is running on port ${PORT}."
echo ""
echo "iPhone Shortcut:"
echo "  1. Shortcuts app → New Shortcut → Add Action → 'Get Contents of URL'"
echo "  2. URL: http://100.78.73.64:${PORT}/restart-gateway?token=${JARVIS_WAKE_TOKEN}"
echo "     (Use your Pixel Tailscale IP if different; see pixel-edge-server-setup.md)"
echo "  3. Optional: Add 'Show Result' or 'Show Notification' to see 'OK gateway restarting'"
echo ""
echo "From any device on Tailscale you can also run:"
echo "  curl \"http://100.78.73.64:${PORT}/restart-gateway?token=${JARVIS_WAKE_TOKEN}\""