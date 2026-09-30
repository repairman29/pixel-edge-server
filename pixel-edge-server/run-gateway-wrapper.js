#!/data/data/com.termux/files/usr/bin/env node
// Wrapper to run clawdbot with proper TMPDIR

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Ensure tmp directory exists
const tmpDir = process.env.HOME + '/tmp';
if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
}

// Set environment variables
process.env.TMPDIR = tmpDir;
process.env.TEMP = tmpDir;
process.env.TMP = tmpDir;

console.log('Starting Clawdbot Gateway...');
console.log('TMPDIR:', process.env.TMPDIR);
console.log('CWD:', process.cwd());

// Change to JARVIS directory
process.chdir(process.env.HOME + '/JARVIS');

// Run clawdbot gateway
const child = spawn('./node_modules/.bin/clawdbot', ['gateway', 'run', '--allow-unconfigured', '--port', '18789', '--bind', 'lan'], {
    stdio: 'inherit',
    env: process.env
});

child.on('error', (err) => {
    console.error('Failed to start:', err);
    process.exit(1);
});

child.on('exit', (code) => {
    console.log('Gateway exited with code:', code);
    process.exit(code);
});
