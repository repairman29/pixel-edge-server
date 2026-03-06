#!/data/data/com.termux/files/usr/bin/bash
# Patch and start clawdbot with custom tmpdir

echo "=== Patching Clawdbot for Android ==="
echo ""

cd ~/JARVIS

# Create a wrapper that patches os.tmpdir()
cat > ~/start-gateway-patched.js << 'NODEWRAPPER'
const os = require('os');

// Override tmpdir to use home directory
const originalTmpdir = os.tmpdir;
os.tmpdir = function() {
    return process.env.TMPDIR || process.env.HOME + '/tmp';
};

// Set environment
process.env.TMPDIR = process.env.HOME + '/tmp';
process.env.TEMP = process.env.TMPDIR;
process.env.TMP = process.env.TMPDIR;

// Create directory
const fs = require('fs');
const path = require('path');
const tmpDir = os.tmpdir();

if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
}

// Now require and run clawdbot
const { spawn } = require('child_process');

const child = spawn('node', [
    './node_modules/@anthropic-ai/clawdbot/bin/clawdbot',
    'gateway',
    'run'
], {
    stdio: 'inherit',
    cwd: process.env.HOME + '/JARVIS'
});

child.on('error', (err) => {
    console.error('Failed to start:', err);
});

child.on('exit', (code) => {
    console.log('Gateway exited with code:', code);
});
NODEWRAPPER

echo "Created patched wrapper"
echo ""

# Ensure tmp exists
mkdir -p ~/tmp
mkdir -p ~/tmp/clawdbot

echo "Starting gateway with patched tmpdir..."
node ~/start-gateway-patched.js
