#!/usr/bin/env bash
# Install OpenCode in the Pixel VM and run opencode serve as a user service.
# Jarvis can then use OpenCode for coding tasks (opencode run --attach or HTTP API).
# Run from your Mac. Uses Tailscale by default; for USB: adb forward tcp:8022 tcp:8022 then use droid@127.0.0.1
# Usage: ./scripts/setup-opencode-in-vm.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"

echo "=== Installing OpenCode and opencode-serve service on ${TARGET} ==="

ssh $SSH_OPTS "$TARGET" bash -s << REMOTE
set -e
export PATH="\$HOME/.opencode/bin:\$PATH"

# Install OpenCode (linux-arm64 supported by official script)
if ! command -v opencode >/dev/null 2>&1; then
  echo "Downloading and installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
  export PATH="\$HOME/.opencode/bin:\$PATH"
else
  echo "OpenCode already installed: \$(opencode --version 2>/dev/null || echo 'unknown')"
fi

# Ensure PATH for this session
export PATH="\$HOME/.opencode/bin:\$PATH"
OPENCODE_BIN="\$HOME/.opencode/bin/opencode"

# Systemd user service: opencode serve (headless API for Jarvis / TUI attach)
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/opencode-serve.service << SVC
[Unit]
Description=OpenCode headless server (for Jarvis / opencode run --attach)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=\${OPENCODE_BIN} serve --port $OPENCODE_PORT --hostname 127.0.0.1
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SVC

# Enable lingering if needed, reload, enable, start
sudo loginctl enable-linger "\$USER" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable opencode-serve.service
systemctl --user restart opencode-serve.service
sleep 2
systemctl --user status opencode-serve.service --no-pager || true

# Drop OpenCode instructions into workspace so Jarvis sees them
mkdir -p ~/.openclaw/workspace
cat > ~/.openclaw/workspace/OPENCODE.md << 'JARVIS'
# OpenCode (for Jarvis)

OpenCode server runs at **http://127.0.0.1:4096** (inside this VM). Use it for coding tasks in a repo.

- **Run a task:** exec with workdir set to the repo, command: ~/.opencode/bin/opencode run --attach http://127.0.0.1:4096 \"your prompt here\"
- **API:** http://127.0.0.1:4096/doc (sessions, messages, files).
- **Health:** curl -s http://127.0.0.1:4096/global/health
JARVIS
REMOTE

echo ""
echo "OpenCode serve is running at http://127.0.0.1:${OPENCODE_PORT} inside the VM."
echo "Jarvis can use it with: opencode run --attach http://127.0.0.1:${OPENCODE_PORT} \"prompt\" (with cwd set to a repo)."
echo "API spec: http://127.0.0.1:${OPENCODE_PORT}/doc"
echo ""
echo "One-time: SSH in and run 'opencode init' (and optionally 'opencode auth login') to configure providers/API keys."
echo "To check: ssh -p 8022 $TARGET 'systemctl --user status opencode-serve'"