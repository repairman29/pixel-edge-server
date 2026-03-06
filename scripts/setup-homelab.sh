#!/bin/bash
# setup-homelab.sh — Deploy the Pixel homelab Docker stack (Ollama + Jellyfin + NGINX).
#
# Run from your Mac:
#   bash scripts/setup-homelab.sh
#
# Environment overrides:
#   PIXEL_HOST   — SSH target (default: droid@100.78.73.64)
#   PIXEL_PORT   — SSH port   (default: 8022)
#   PULL_MODEL   — Ollama model to pull after launch (default: llama3.2:3b, set to "" to skip)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"
PULL_MODEL="${PULL_MODEL:-llama3.2:3b}"

vm_banner "Pixel Homelab Stack — Docker Deploy"
echo "  Stack  : Ollama + Jellyfin + NGINX"
echo ""

# ── Step 1: copy homelab files ────────────────────────────────────────────────
echo "==> [1/4] Copying homelab files to VM..."

vm_ssh mkdir -p ~/homelab
vm_scp homelab/docker-compose.yml homelab/nginx.conf "~/homelab/"

echo "  Files copied."

# ── Step 2: check Docker is available ─────────────────────────────────────────
echo ""
echo "==> [2/4] Checking Docker in VM..."
vm_ssh_heredoc <<'REMOTE'
if ! command -v docker &>/dev/null; then
  echo "  Docker not found! Installing..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$(whoami)"
  echo "  Docker installed. You may need to log out and back in."
else
  echo "  Docker $(docker --version | awk '{print $3}' | tr -d ,) found."
fi

if ! docker compose version &>/dev/null 2>&1; then
  echo "  Installing docker compose plugin..."
  sudo apt-get install -y docker-compose-plugin
fi
echo "  Docker Compose $(docker compose version --short) found."
REMOTE

# ── Step 3: pull images & start stack ─────────────────────────────────────────
echo ""
echo "==> [3/4] Pulling images and starting stack..."
vm_ssh_heredoc <<'REMOTE'
cd ~/homelab
echo "  Pulling images (this may take a few minutes on first run)..."
docker compose pull
echo "  Starting stack..."
docker compose up -d
echo "  Stack status:"
docker compose ps
REMOTE

# ── Step 4: pull Ollama model ─────────────────────────────────────────────────
if [ -n "${PULL_MODEL}" ]; then
  echo ""
  echo "==> [4/4] Pulling Ollama model: ${PULL_MODEL}..."
  echo "  (This downloads the model weights — may take a few minutes)"
  vm_ssh "docker exec ollama ollama pull '${PULL_MODEL}'" || {
    echo "  Model pull failed or still starting; retry with:"
    echo "  ssh -p ${VM_PORT} ${VM_HOST} \"docker exec ollama ollama pull ${PULL_MODEL}\""
  }
else
  echo ""
  echo "==> [4/4] Skipping model pull (PULL_MODEL is empty)."
  echo "  Pull a model later with:"
  echo "  ssh -p ${VM_PORT} ${VM_HOST} 'docker exec ollama ollama pull llama3.2:3b'"
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       Homelab Stack Ready                    ║"
echo "╚══════════════════════════════════════════════╝"
echo "  Jellyfin   : http://100.78.73.64:8096"
echo "  Ollama API : http://100.78.73.64:11434"
echo "  NGINX      : http://100.78.73.64"
echo "    /          → Jellyfin"
echo "    /ollama/   → Ollama LLM API"
echo "    /ai/       → Claude Gateway"
echo ""
echo "  Via Claude Gateway (model routing):"
echo "  Add LOCAL_LLM_URL=http://127.0.0.1:11434/v1/chat/completions"
echo "  to ~/.config/claude-gateway/.env on the VM, then restart claude-gateway."
echo ""
echo "  Manage the stack:"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'cd ~/homelab && docker compose ps'"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'cd ~/homelab && docker compose logs -f'"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'cd ~/homelab && docker compose down'"
