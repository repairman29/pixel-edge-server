const { spawn } = require('child_process');
const child = spawn(
  '/data/data/com.termux/files/usr/bin/node',
  ['/data/data/com.termux/files/home/JARVIS/scripts/start-gateway-background.js'],
  {
    cwd: '/data/data/com.termux/files/home/JARVIS',
    detached: true,
    stdio: 'ignore',
    env: {
      HOME: '/data/data/com.termux/files/home',
      TMPDIR: '/data/data/com.termux/files/home/tmp',
      PORT: '18789'
    }
  }
);
child.unref();
console.log('spawned gateway');
