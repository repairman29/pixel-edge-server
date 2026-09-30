#!/data/data/com.termux/files/usr/bin/bash
# Ultimate fix: Intercept mkdir calls

echo "=== Ultimate Clawdbot Fix ==="
echo ""

cd ~/JARVIS

# Create a Node.js interceptor
cat > ~/clawdbot-intercept.js << 'INTERCEPTOR'
const Module = require('module');
const originalRequire = Module.prototype.require;
const fs = require('fs');
const path = require('path');

// Override fs.mkdir to redirect /tmp to ~/tmp
const originalMkdir = fs.mkdir;
const originalMkdirSync = fs.mkdirSync;

function redirectPath(p) {
    if (p.startsWith('/tmp') && !p.startsWith(process.env.HOME + '/tmp')) {
        const newPath = p.replace('/tmp', process.env.HOME + '/tmp');
        console.log('Redirecting mkdir:', p, '->', newPath);
        return newPath;
    }
    return p;
}

fs.mkdir = function(path, options, callback) {
    path = redirectPath(path);
    return originalMkdir.call(fs, path, options, callback);
};

fs.mkdirSync = function(path, options) {
    path = redirectPath(path);
    return originalMkdirSync.call(fs, path, options);
};

// Ensure tmp exists
const tmpDir = process.env.HOME + '/tmp';
if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
}

console.log('Interceptor loaded, tmpdir:', tmpDir);
console.log('CWD:', process.cwd());

// Change to JARVIS directory
process.chdir(process.env.HOME + '/JARVIS');
console.log('Changed to:', process.cwd());

// Find clawdbot path - try multiple locations
const possiblePaths = [
    './node_modules/.bin/clawdbot',
    './node_modules/@anthropic-ai/clawdbot/bin/clawdbot',
    './node_modules/@anthropic-ai/sdk/bin/clawdbot'
];

let clawdbotPath = null;
for (const p of possiblePaths) {
    const fullPath = process.cwd() + '/' + p;
    console.log('Checking:', fullPath);
    if (fs.existsSync(fullPath)) {
        clawdbotPath = fullPath;
        console.log('Found at:', clawdbotPath);
        break;
    }
}

if (!clawdbotPath) {
    console.error('Could not find clawdbot binary');
    process.exit(1);
}

// Spawn clawdbot as child process
const { spawn } = require('child_process');
const child = spawn('node', [clawdbotPath, 'gateway', 'run'], {
    stdio: 'inherit',
    cwd: process.cwd()
});

child.on('error', (err) => {
    console.error('Failed to start:', err);
});

child.on('exit', (code) => {
    console.log('Gateway exited with code:', code);
});
INTERCEPTOR

echo "Created interceptor script"
echo ""

# Ensure tmp exists
mkdir -p ~/tmp
mkdir -p ~/tmp/clawdbot

echo "Starting gateway with interceptor..."
node ~/clawdbot-intercept.js 2>&1
