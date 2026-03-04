#!/usr/bin/env bash
# Run from your Mac (USB or Tailscale). Copies gateway crash logs from the VM to your machine.
# Usage: ./scripts/capture-gateway-crash-log.sh [droid@127.0.0.1]
# Requires: adb forward tcp:8022 tcp:8022 (for 127.0.0.1) or Tailscale for 100.78.73.64

set -e
TARGET="${1:-droid@100.78.73.64}"
SSH_OPTS="-p 8022 -o ConnectTimeout=15 -o StrictHostKeyChecking=no"
OUT="${2:-./gateway-crash-log.txt}"

echo "Fetching gateway logs from ${TARGET}..."
ssh $SSH_OPTS "$TARGET" 'journalctl --user -u openclaw-gateway -n 200 --no-pager 2>/dev/null; echo "---"; dmesg 2>/dev/null | tail -50' > "$OUT" 2>&1 || true
echo "Written to ${OUT}"
echo "Last 30 lines:"
tail -30 "$OUT"
