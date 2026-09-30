#!/bin/bash
exec > /sdcard/run-log.txt 2>&1
echo "Running at $(date)"

echo "Checking home..."
ls -la ~/ 2>&1

echo ""
echo "Checking JARVIS..."
ls -la ~/JARVIS/ 2>&1

echo ""
echo "Checking node..."
which node 2>&1
node --version 2>&1

echo ""
echo "Checking npm..."
which npm 2>&1
npm --version 2>&1

echo ""
echo "Checking clawdbot..."
ls -la ~/JARVIS/node_modules/.bin/clawdbot 2>&1

echo ""
echo "Done at $(date)"
