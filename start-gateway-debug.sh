#!/data/data/com.termux/files/usr/bin/bash
cd ~/JARVIS
export PORT=18789
export BIND_LAN=1
export TMPDIR=~/tmp
mkdir -p $TMPDIR

echo "Starting gateway on port 18789..."
echo "Current directory: $(pwd)"
echo "Node version: $(node --version)"

# Try to start gateway with visible errors
node -e "
const { spawn } = require('child_process');
const child = spawn('npx', ['clawdbot', 'gateway', 'run', '--allow-unconfigured', '--port', '18789'], {
  env: { ...process.env, PORT: '18789', BIND_LAN: '1' },
  stdio: 'inherit'
});
child.on('error', (err) => console.error('Spawn error:', err));
child.on('exit', (code) => console.log('Exit code:', code));
" 2>&1 | tee ~/gateway-start.log
