# Complete OpenClaw Setup on Pixel 8 Pro

## What We're Building
A fully autonomous AI agent running natively on your Pixel with:
- ✅ OpenClaw (Clawdbot) for autonomous reasoning
- ✅ Local LLM (Gemma 3B) on NPU
- ✅ Telegram bot interface
- ✅ Full system access (shell, files, processes)
- ✅ Self-improving capabilities

## Prerequisites
1. Termux app installed from F-Droid
2. Jarvis app running (for LLM API)
3. ~2GB free space
4. 30-45 minutes for installation

## Step 1: Open Termux

On your Pixel:
1. Open the **Termux** app
2. Grant storage permission when prompted
3. Wait for initial setup to complete

## Step 2: Copy Installation Script

In Termux, run:
```bash
# Copy script from shared storage to Termux home
cp /sdcard/install_openclaw_termux.sh ~
cd ~
chmod +x install_openclaw_termux.sh
```

## Step 3: Run Installation

```bash
# This will take 20-45 minutes
./install_openclaw_termux.sh
```

The script will:
1. ✅ Update packages
2. ✅ Install Node.js, Rust, Python
3. ✅ Clone OpenClaw repository
4. ✅ Patch clipboard for Android
5. ✅ Build the project
6. ✅ Create config for Jarvis integration
7. ✅ Set up auto-start scripts

## Step 4: Start Services

**First, make sure Jarvis is running:**
- Open Jarvis app
- Tap "START JARVIS"
- Wait for "Model loaded ✓"

**Then in Termux, start OpenClaw:**
```bash
~/start-openclaw.sh
```

**Verify it's running:**
```bash
~/status-openclaw.sh
```

You should see:
```
✓ OpenClaw is running
[logs showing startup...]
```

## Step 5: Test the Bot

Open Telegram and message **@jarvis2_pixel_bot**:

```
!system
!shell whoami
!ls /sdcard
!ping google.com
```

## Troubleshooting

### "clipboard module not found"
This is expected - we patch it during install. If build fails:
```bash
cd ~/openclaw
npm install --legacy-peer-deps
npm run build
```

### "Cannot find module"
Make sure you're in the openclaw directory:
```bash
cd ~/openclaw
ls bin/
```

### "Port 18789 in use"
Kill existing process:
```bash
pkill -f openclaw
~/start-openclaw.sh
```

### "LLM not responding"
Check Jarvis is running:
```bash
curl http://127.0.0.1:9090/status
```

## Architecture

```
Telegram (@jarvis2_pixel_bot)
         ↓
OpenClaw Gateway (Termux :18789)
         ↓
Jarvis HTTP API (:9090)
         ↓
Gemma 3B (Pixel NPU)
         ↓
Android System
```

## What OpenClaw Can Do

Once running, the bot can:
- ✅ Execute any shell command
- ✅ Read/write files
- ✅ Manage processes
- ✅ Monitor system resources
- ✅ Run Python scripts
- ✅ Make HTTP requests
- ✅ Search files
- ✅ Tail logs
- ✅ Self-update and improve

## Making It Autonomous

To enable autonomous mode, send:
```
!autonomous on
```

This allows OpenClaw to:
- Execute commands without confirmation
- Write files automatically
- Start/stop processes
- Self-diagnose and fix issues

**⚠️ Warning:** Autonomous mode gives the bot full system access. Only enable if you trust it completely.

## Manual Control Commands

In Telegram, use these prefixes:
- `!shell <cmd>` - Execute shell command
- `!ls <path>` - List directory
- `!read <file>` - Read file contents
- `!write <file> <content>` - Write to file
- `!python <code>` - Execute Python
- `!system` - Get system info
- `!network` - Network diagnostics
- `!ps` - List processes
- `!kill <pid>` - Kill process
- `!find <pattern>` - Search files
- `!grep <pattern> <file>` - Search text

## Persistence

To keep OpenClaw running:
1. Enable "Keep Termux in background" in Android settings
2. The `.termux/boot` script auto-starts on device boot
3. Or run manually: `~/start-openclaw.sh`

## Updates

To update OpenClaw:
```bash
cd ~/openclaw
git pull
npm install
npm run build
~/stop-openclaw.sh
~/start-openclaw.sh
```

## Full Autonomy Achieved! 🎉

Your Pixel 8 Pro is now a fully autonomous AI server with:
- Local LLM reasoning (no cloud dependency)
- Full Linux environment via Termux
- Complete system access
- Telegram remote control
- Self-improvement capabilities

**Try it now:** Message @jarvis2_pixel_bot with `!system` and watch it respond with your device info!