#!/bin/bash
# Run inside termux-chroot
exec > /sdcard/install-log.txt 2>&1

echo "Starting install at $(date)"

echo "HOME=$HOME"
echo "Current dir: $(pwd)"

echo "Checking npm..."
which npm
npm --version

echo ""
echo "Checking node..."
which node
node --version

echo ""
echo "Checking JARVIS..."
ls -la ~/JARVIS/ 2>&1 | head -20

echo ""
echo "Checking for package.json..."
ls ~/JARVIS/package.json 2>&1

echo ""
echo "Installing clawdbot..."
cd ~/JARVIS
npm install clawdbot 2>&1

echo ""
echo "Done at $(date)"
