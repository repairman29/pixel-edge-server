#!/usr/bin/env bash
# Run Ollama in Docker in the VM for a local OpenAI-compatible LLM endpoint.
# Run from your Mac. Usage: ./scripts/setup-local-llm.sh [droid@100.78.73.64]

set -e

SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
TARGET="${1:-droid@100.78.73.64}"

echo "=== Setting up local LLM (Ollama) in VM (${TARGET}) ==="

ssh $SSH_OPTS "$TARGET" bash -s << 'REMOTE'
set -e
# Ollama official image supports linux/arm64
docker pull ollama/ollama 2>/dev/null || true
docker stop llm 2>/dev/null || true
docker rm llm 2>/dev/null || true
docker run -d --name llm -p 11434:11434 -v ollama:/root/.ollama ollama/ollama
sleep 3
# Pull a small model (optional; user can run ollama run <model> later)
docker exec llm ollama pull tinyllama 2>/dev/null || echo "Pull tinyllama skipped or failed; run manually: docker exec llm ollama pull tinyllama"
echo "Ollama is running. OpenAI-compatible API: http://127.0.0.1:11434"
REMOTE

echo ""
echo "Local LLM (Ollama) is running in the VM. In OpenClaw, set model endpoint to http://127.0.0.1:11434/v1"
echo "To pull another model: ssh -p 8022 $TARGET 'docker exec llm ollama pull <model>'"