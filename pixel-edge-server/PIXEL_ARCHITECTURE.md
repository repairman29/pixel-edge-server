# Pixel Edge Server Architecture

## Overview

Your Pixel 8 Pro runs a sophisticated AI stack with multiple environments:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Android (Pixel 8 Pro)                        │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    Termux Environment                           │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │ │
│  │  │  ~/openclaw  │  │ ~/.config/   │  │   ~/.clawdbot/       │ │ │
│  │  │  (native)    │  │ openclaw/    │  │   (legacy config)    │ │ │
│  │  │  Port 18790  │  │  Config      │  │   Port 18789         │ │ │
│  │  │  Discord     │  │              │  │   (DISABLED)         │ │ │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘ │ │
│  │                            ▲                                    │ │
│  │                            │                                    │ │
│  │  ┌───────────────────────┴────────────────────────────────┐    │ │
│  │  │              Chroot Linux Environment                   │    │ │
│  │  │  ┌────────────────────────────────────────────────────┐ │    │ │
│  │  │  │  /home/clawd/                                    │ │    │ │
│  │  │  │  Port 18789 (native OpenClaw)                    │ │    │ │
│  │  │  │  Previously had Discord + Telegram               │ │    │ │
│  │  │  │  Currently: NOT RUNNING                          │ │    │ │
│  │  │  └────────────────────────────────────────────────────┘ │    │ │
│  │  └──────────────────────────────────────────────────────────┘    │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ USB/WiFi
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         MacBook (Maclawd)                           │
│  Ports: 18789, 18791, 18792                                         │
│  Status: RUNNING                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Port Allocation Strategy

To avoid conflicts between Maclawd (MacBook) and Pixel environments:

| Port | Usage | Status |
|------|-------|--------|
| 18789 | Maclawd (MacBook) | ✅ Active |
| 18790 | Jarvy (Pixel native) | ✅ New target |
| 18791 | Maclawd (MacBook) | ✅ Active |
| 18792 | Maclawd (MacBook) | ✅ Active |

**Rule:** Never use ports 18789-18792 on Pixel to avoid conflicts with Maclawd.

## Current Pixel Configuration

### 1. Native Termux OpenClaw (~/openclaw)

**Location:** `/data/data/com.termux/files/home/openclaw`

**Config:** `/data/data/com.termux/files/home/.config/openclaw/config.json`

```json
{
  "gateway": {
    "port": 18790,  // Changed from 18791 to avoid Maclawd conflict
    "mode": "local",
    "bind": "lan"
  },
  "channels": {
    "discord": {
      "enabled": true
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": false  // Disabled to avoid conflicts
      },
      "discord": {
        "enabled": true,
        "token": "<DISCORD_BOT_TOKEN>"
      }
    }
  }
}
```

**Key Points:**
- Uses Discord only (no Telegram to avoid conflicts)
- Port 18790 (no conflict with Maclawd)
- Full bash commands enabled
- Workspace: ~/JARVIS
- Model: farm/MiniCPM4.1 Instruct

### 2. Chroot Environment (/home/clawd)

**Location:** `/data/data/com.termux/files/home/clawd` (chroot Linux)

**Previous Config:** Used ports 18789 + 18791

**Status:** Currently not running (conflicts with Maclawd)

**To restart:**
```bash
# From Termux, enter chroot
proot-distro login debian  # or your distro

# Then start gateway
cd /home/clawd
clawdbot gateway --port 18793  # Use different port!
```

## How to Start Jarvy (Discord Bot)

### Option 1: Native Termux (Recommended - Port 18790)

```bash
# Kill any existing instances
pkill -9 -f clawdbot

# Start fresh
cd ~/openclaw
node dist/entry.js gateway --bind loopback --port 18790
```

**Or with logging:**
```bash
cd ~/openclaw
nohup node dist/entry.js gateway --bind loopback --port 18790 > ~/openclaw.log 2>&1 &
```

### Option 2: Chroot Environment (Port 18793+)

```bash
# Enter chroot
proot-distro login debian

# Navigate to clawd
cd /home/clawd

# Start with non-conflicting port
clawdbot gateway --port 18793
```

## Discord Bot Authorization

Before Jarvy will appear online, you must authorize it:

**Authorization URL:**
```
https://discord.com/oauth2/authorize?client_id=1478435625266053333&permissions=8&scope=bot
```

1. Open URL in browser
2. Select your Discord server
3. Authorize "Jarvy"
4. Bot will appear online

## Common Issues & Solutions

### Issue: "Port in use" error

**Cause:** Maclawd on MacBook is using port 18789/18791

**Solution:** Use port 18790 or higher

```bash
# Check what's using the port
netstat -tlnp | grep 18789

# Kill conflicting process
pkill -9 -f clawdbot

# Restart on different port
node dist/entry.js gateway --port 18790
```

### Issue: Discord "Failed to resolve application id"

**Cause:** Invalid or expired Discord token

**Solution:** 
1. Go to https://discord.com/developers/applications
2. Find your bot
3. Reset token
4. Update `~/.config/openclaw/config.json`

### Issue: Telegram getUpdates conflicts

**Cause:** Multiple instances using same Telegram bot token

**Solution:** Disable Telegram in config:
```json
"telegram": {
  "enabled": false
}
```

## Model Configuration

### Using farm/MiniCPM4.1 (Local Pixel Model)

**Config location:** `~/.config/openclaw/config.json`

```json
{
  "models": {
    "providers": {
      "farm": {
        "baseUrl": "http://127.0.0.1:8889/v1",
        "apiKey": "sk-local-farm",
        "api": "openai-completions",
        "models": [
          {
            "id": "minicpm4",
            "name": "MiniCPM4 (Pixel)",
            "contextWindow": 200000
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "farm/MiniCPM4.1 Instruct"
      }
    }
  }
}
```

**Requirements:**
- MiniCPM4 model must be running on port 8889
- Or accessible via local LLM server

## Commands & Capabilities

Once Jarvy is connected to Discord:

| Command | Description |
|---------|-------------|
| `!system` | Get system info |
| `!shell <cmd>` | Execute shell command |
| `!ls <path>` | List directory |
| `!read <file>` | Read file contents |
| `!python <code>` | Execute Python |
| `!ps` | List processes |
| `!find <pattern>` | Search files |

**Bash commands:** Enabled (`"bash": true` in config)

## Status Check

```bash
# Check if gateway is running
ps | grep claw

# Check port usage
netstat -tlnp | grep 187

# Check Discord config
cat ~/.config/openclaw/config.json | jq '.plugins.entries.discord'

# View logs (if started with nohup)
tail -f ~/openclaw.log
```

## Architecture Decision

**Why native Termux instead of chroot?**

1. **Simpler setup** - No chroot management needed
2. **Direct access** to Android system via Termux APIs
3. **Discord works** without chroot networking issues
4. **Easier debugging** - direct access to logs and processes
5. **Lower overhead** - no chroot filesystem layer

**When to use chroot:**
- Need full Linux environment
- Running complex server stacks
- Need specific Linux libraries
- Running multiple isolated services

## Next Steps

1. ✅ Kill existing processes (done)
2. ✅ Update config with new Discord token (done)
3. ✅ Change port to 18790 (done)
4. 🔄 Start Jarvy gateway
5. 🔄 Verify Discord connection
6. 🔄 Test commands

## Files Reference

| File | Location | Purpose |
|------|----------|---------|
| `config.json` | `~/.config/openclaw/` | Main OpenClaw config |
| `clawdbot` | `~/.clawdbot/` | Legacy clawdbot config (DISABLED) |
| `openclaw/` | `~/openclaw/` | OpenClaw installation |
| `build-jarvis-on-pixel.sh` | `~/` | APK build script |
| `chroot-gateway.log` | `~/` | Chroot gateway logs |

---

**Last Updated:** 2026-03-08
**Status:** Configuration updated, ready to start gateway
