# Clawdbot Setup on Pixel via Termux

## Status

✅ **Completed:**
- Clawdbot installed via npm globally
- Module location: `/data/data/com.termux/files/usr/lib/node_modules/clawdbot`
- Pairing code: `WT4LUXF4`
- Telegram user ID: `8705004824`

❌ **Issue:**
- Runtime error with `@mariozechner/clipboard` native module
- Exit code 1 when running clawdbot commands

## What Was Done

### 1. SSH Connection Established
```bash
# Port forward via ADB
adb forward tcp:8022 tcp:8022

# SSH connection working
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1
```

### 2. Clawdbot Installed
```bash
# Via SSH
npm install -g clawdbot
# Result: added 506 packages in 1m
```

### 3. Pairing Attempt
```bash
clawdbot pairing approve telegram WT4LUXF4
# Result: Exit code 1 (runtime error)
```

## Runtime Error

```
Error: Cannot find module '../build/Release/clipboard.node'
    at Module.require (node:internal/modules/cjs/loader:1503:12)
    at require (node:internal/modules/helpers:152:16)
    at Object.<anonymous> (/data/data/com.termux/files/usr/lib/node_modules/clawdbot/node_modules/@mariozechner/clipboard/index.js:40:29)
```

## Solutions

### Option 1: Fix Native Module (Recommended)

In Termux:
```bash
# Install build tools
pkg install build-essential python -y

# Rebuild native modules
cd /data/data/com.termux/files/usr/lib/node_modules/clawdbot
npm rebuild

# Or reinstall with build from source
npm uninstall -g clawdbot
npm install -g clawdbot --build-from-source
```

### Option 2: Use Pre-built Binary

Check if there's a pre-built binary:
```bash
# Check clawdbot repo
ls /data/data/com.termux/files/usr/lib/node_modules/clawdbot/bin/

# Run directly
node /data/data/com.termux/files/usr/lib/node_modules/clawdbot/bin/clawdbot pairing approve telegram WT4LUXF4
```

### Option 3: Manual Pairing File

Create pairing file manually:
```bash
# Create config directory
mkdir -p ~/.config/clawdbot

# Create pairings file
cat > ~/.config/clawdbot/pairings.json << 'EOF'
{
  "telegram": {
    "8705004824": {
      "code": "WT4LUXF4",
      "approved": true,
      "timestamp": "2026-03-05T08:50:00Z"
    }
  }
}
EOF
```

### Option 4: Run on Mac Instead

If Termux environment is problematic, run Clawdbot on Mac instead:
```bash
# On Mac
npm install -g clawdbot
clawdbot pairing approve telegram WT4LUXF4
```

## Current State

**Jarvis Android:** ✅ Running (Model loaded, Telegram connected)
**Termux SSH:** ✅ Working (Port 8022 forwarded)
**Bridge Script:** ✅ Running (Python bridge active)
**Clawdbot:** ⚠️ Installed but runtime error

## Next Steps

1. **Fix Clawdbot**: Try Option 1 or 2 above
2. **Alternative**: Use Jarvis bridge without Clawdbot
3. **Hybrid**: Keep Jarvis on Pixel, Clawdbot on Mac

## Files Created

- `/sdcard/jarvis/install_clawdbot.sh` - Installation script
- `~/.ssh/termux_pixel` - SSH key
- `/data/data/com.termux/files/usr/lib/node_modules/clawdbot/` - Clawdbot module

## Working Commands

Via SSH to Termux:
```bash
# Test connection
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1 'echo OK'

# List files
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1 'ls -la /sdcard'

# Run bridge
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1 'python3 ~/jarvis_bridge.py'

# Check processes
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1 'ps aux'
```

## Support

If stuck:
1. Check Clawdbot issues: `npm list -g clawdbot`
2. Verify Node version: `node --version`
3. Check for updates: `npm update -g clawdbot`
4. Use alternative: Run Clawdbot on Mac with SSH to Pixel