#!/data/data/com.termux/files/usr/bin/node
/**
 * jarvis-daemon.js — daemonize the clawdbot gateway properly.
 *
 * Strategy: use a shell double-fork via `setsid nohup` so the process
 * is reparented to init (PID 1) and survives the adb session closing.
 *
 * Usage:
 *   node jarvis-daemon.js          # start gateway daemon
 *   node jarvis-daemon.js --kill   # stop it
 *   node jarvis-daemon.js --status # check status
 */

const fs = require('fs');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const HOME = process.env.HOME || '/data/data/com.termux/files/home';
const PREFIX = '/data/data/com.termux/files/usr';
const JARVIS_DIR = path.join(HOME, 'JARVIS');
const TMP_DIR = path.join(HOME, 'tmp');
const LOG_FILE = path.join(HOME, 'gateway.log');
const PID_FILE = path.join(TMP_DIR, 'gateway.pid');
const NODE = path.join(PREFIX, 'bin', 'node');
const NPX = path.join(PREFIX, 'bin', 'npx');

try { fs.mkdirSync(TMP_DIR, { recursive: true }); } catch (_) {}

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  try { fs.appendFileSync(LOG_FILE, line); } catch (_) {}
  try { process.stdout.write(line); } catch (_) {}
}

function readPid() {
  try { return parseInt(fs.readFileSync(PID_FILE, 'utf8').trim()); } catch (_) { return null; }
}

function isRunning(pid) {
  if (!pid || isNaN(pid)) return false;
  try { process.kill(pid, 0); return true; } catch (_) { return false; }
}

function killGateway() {
  const pid = readPid();
  if (pid && isRunning(pid)) {
    try { process.kill(pid, 'SIGTERM'); log(`sent SIGTERM to PID ${pid}`); } catch (_) {}
  }
  try { execFileSync(path.join(PREFIX, 'bin', 'pkill'), ['-f', 'clawdbot gateway'], { stdio: 'ignore' }); } catch (_) {}
  try { execFileSync(path.join(PREFIX, 'bin', 'pkill'), ['-f', 'gateway run --allow-unconfigured'], { stdio: 'ignore' }); } catch (_) {}
  try { fs.unlinkSync(PID_FILE); } catch (_) {}
}

if (process.argv.includes('--kill')) {
  killGateway();
  log('stopped');
  process.exit(0);
}

if (process.argv.includes('--status')) {
  const pid = readPid();
  const running = isRunning(pid);
  log(`gateway ${running ? `running (PID ${pid})` : 'not running'}`);
  process.exit(running ? 0 : 1);
}

// Kill any stale gateway
killGateway();

// Build env
const env = [
  `HOME=${HOME}`,
  `PATH=${PREFIX}/bin:${process.env.PATH || '/usr/bin:/bin'}`,
  `TMPDIR=${TMP_DIR}`,
  `TMP=${TMP_DIR}`,
  `TEMP=${TMP_DIR}`,
  `PORT=18789`,
  `BIND_LAN=1`,
];

// Add GROQ key if present in .env
try {
  const envFile = path.join(HOME, '.clawdbot', '.env');
  const lines = fs.readFileSync(envFile, 'utf8').split('\n');
  for (const line of lines) {
    const m = line.trim().match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (m) env.push(`${m[1]}=${m[2].replace(/^["']|["']$/g, '').trim()}`);
  }
} catch (_) {}

// Add NODE_OPTIONS for proot network patch if available
const patchPath = path.join(JARVIS_DIR, 'scripts', 'patch-proot-network.js');
const nodeOpts = fs.existsSync(patchPath) ? `--require ${patchPath}` : '';
if (nodeOpts) env.push(`NODE_OPTIONS=${nodeOpts}`);

// The gateway command
const gwArgs = [NPX, 'clawdbot', 'gateway', 'run', '--allow-unconfigured', '--port', '18789', '--bind', 'lan'];

// Use sh -c with setsid + nohup to fully daemonize.
// setsid creates a new session (detaches from terminal).
// nohup prevents SIGHUP when parent exits.
// The shell then execs env + gateway.
const envStr = env.map(e => `${e.split('=')[0]}="${e.slice(e.indexOf('=') + 1).replace(/"/g, '\\"')}"`).join(' ');
const gwCmd = gwArgs.map(a => `"${a}"`).join(' ');

// Write a small shell script that exec's the gateway so there's no intermediate sh
const LAUNCH_SH = path.join(TMP_DIR, 'launch-gateway.sh');
const script = [
  '#!/data/data/com.termux/files/usr/bin/bash',
  ...env.map(e => `export ${e}`),
  `cd ${JARVIS_DIR}`,
  `exec ${gwArgs.join(' ')} >> "${LOG_FILE}" 2>&1`,
].join('\n') + '\n';

fs.writeFileSync(LAUNCH_SH, script, { mode: 0o755 });
log(`launch script written to ${LAUNCH_SH}`);

// Use setsid to daemonize: spawn sh -c "setsid nohup ... &"
// This makes the gateway a session leader with no controlling terminal
const sh = path.join(PREFIX, 'bin', 'bash');
const daemonCmd = `setsid nohup bash "${LAUNCH_SH}" >> "${LOG_FILE}" 2>&1 &\necho $!`;
const result = spawnSync(sh, ['-c', daemonCmd], {
  cwd: JARVIS_DIR,
  stdio: ['ignore', 'pipe', 'pipe'],
  encoding: 'utf8',
});

const pid = parseInt((result.stdout || '').trim());
const stderr = (result.stderr || '').trim();

if (stderr) log(`daemon stderr: ${stderr}`);
if (!isNaN(pid) && pid > 0) {
  try { fs.writeFileSync(PID_FILE, String(pid) + '\n'); } catch (_) {}
  log(`gateway daemon started, setsid PID=${pid}`);
} else {
  log(`WARNING: could not determine daemon PID (stdout="${result.stdout?.trim()}")`);
}

process.exit(0);
