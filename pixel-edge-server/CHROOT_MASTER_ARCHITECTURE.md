# CHROOT MASTER: One Chroot to Rule Them All

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                       ANDROID (Pixel 8 Pro)                          │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                    Termux Base Environment                       ││
│  │                                                                  ││
│  │  ┌─────────────────────────────────────────────────────────┐    ││
│  │  │              CHROOT MASTER (Ubuntu)                    │    ││
│  │  │  ┌──────────────────────────────────────────────────┐   │    ││
│  │  │  │         OpenClaw Gateway (Port 18790)           │   │    ││
│  │  │  │  ┌────────────────────────────────────────┐     │   │    ││
│  │  │  │  │  Discord Bot (@Jarvy)                 │     │   │    ││
│  │  │  │  │  - Real-time messaging               │     │   │    ││
│  │  │  │  │  - Commands: !shell, !system, etc   │     │   │    ││
│  │  │  │  └────────────────────────────────────────┘     │   │    ││
│  │  │  │                                                 │   │    ││
│  │  │  │  ┌────────────────────────────────────────┐     │   │    ││
│  │  │  │  │  MiniCPM4 LLM (farm provider)         │     │   │    ││
│  │  │  │  │  - Port 8889 (local model server)    │     │   │    ││
│  │  │  │  │  - 200K context window               │     │   │    ││
│  │  │  │  │  - On-device NPU inference           │     │   │    ││
│  │  │  │  └────────────────────────────────────────┘     │   │    ││
│  │  │  │                                                 │   │    ││
│  │  │  │  ┌────────────────────────────────────────┐     │   │    ││
│  │  │  │  │  Full Linux Environment              │     │   │    ││
│  │  │  │  │  - bash, python, node, rust          │     │   │    ││
│  │  │  │  │  - Docker-like isolation           │     │   │    ││
│  │  │  │  │  - Access to Android system          │     │   │    ││
│  │  │  │  └────────────────────────────────────────┘     │   │    ││
│  │  │  └──────────────────────────────────────────────────┘   │    ││
│  │  └─────────────────────────────────────────────────────────┘    ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│  Port Allocation:                                                    │
│  • 18790 → CHROOT_MASTER (OpenClaw + Discord)                        │
│  • 8889  → MiniCPM4 (Local LLM)                                    │
│  • No conflict with Maclawd (18789/18791/18792)                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ USB/WiFi
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       MacBook (Maclawd)                              │
│  Ports: 18789, 18791, 18792 (conflict-free with Pixel)              │
│  Status: Separate instance                                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Why Chroot is Superior

### ✅ Full Linux Environment
- Complete bash shell with all standard tools
- Access to `/tmp`, `/home`, `/var` directories
- Standard Linux process management
- Better compatibility with libraries

### ✅ Isolation & Stability
- Separated from Android system
- Cleaner environment for OpenClaw
- Better error handling
- Persistent `/tmp` across reboots

### ✅ Maximum Capabilities
- **Discord**: Full bot with message content intents
- **MiniCPM4**: Local LLM running on Pixel NPU
- **Commands**: bash, python, file operations
- **Workspace**: Full access to ~/JARVIS
- **Plugins**: extensible architecture

## Configuration Structure

### CHROOT_MASTER Config (`~/.config/openclaw/config.json`)

```json
{
  "gateway": {
    "port": 18790,          // NO CONFLICT with Maclawd
    "mode": "local",
    "bind": "lan"
  },
  "channels": {
    "discord": {
      "enabled": true,
      "groupPolicy": "open"
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": false    // DISABLED to avoid conflicts
      },
      "discord": {
        "enabled": true,
        "token": "YOUR_DISCORD_TOKEN"
      }
    }
  },
  "models": {
    "providers": {
      "farm": {
        "baseUrl": "http://127.0.0.1:8889/v1",
        "apiKey": "sk-local-farm",
        "models": [{
          "id": "minicpm4",
          "name": "MiniCPM4 (Pixel)",
          "contextWindow": 200000
        }]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "farm/minicpm4"
      },
      "workspace": "/data/data/com.termux/files/home/JARVIS"
    }
  }
}
```

## Capabilities Matrix

| Feature | CHROOT_MASTER | Native Termux | Notes |
|---------|---------------|---------------|-------|
| Discord Bot | ✅ Full | ⚠️ Partial | Chroot has better WS handling |
| MiniCPM4 | ✅ Full | ✅ Full | Both work |
| Telegram | ❌ Disabled | ✅ Available | Conflicts with other instances |
| Bash Commands | ✅ Full | ✅ Full | Chroot has more tools |
| File Access | ✅ Full | ✅ Full | Chroot sees Linux paths |
| Python Execution | ✅ Full | ✅ Full | Chroot has better packages |
| Browser Control | ✅ Port 18791 | ❌ None | Chroot includes canvas |
| Process Management | ✅ Better | ✅ Good | Chroot has ps/top/etc |
| Stability | ✅ High | ⚠️ Medium | Chroot is more stable |

## Port Strategy

```
Macbook (Maclawd):
├── Port 18789: Primary gateway
├── Port 18791: Browser/canvas
└── Port 18792: Secondary gateway

Pixel (CHROOT_MASTER):
├── Port 18790: OpenClaw + Discord ✅
├── Port 8889: MiniCPM4 LLM server
└── Port 18791: Canvas (if enabled)

No conflicts! Clean separation of concerns.
```

## How It Works

### 1. Chroot Launch Process

```bash
termux-chroot bash -c '
    # Now in full Linux environment
    export HOME=/home
    cd /data/data/com.termux/files/home/JARVIS
    
    # Start OpenClaw with full capabilities
    ./node_modules/.bin/clawdbot gateway run \
        --port 18790 \
        --bind lan
'
```

### 2. Discord Connection Flow

```
Discord Server
      ↓
Discord WebSocket Gateway
      ↓
CHROOT_MASTER (Port 18790)
      ↓
OpenClaw Agent
      ↓
MiniCPM4 (Port 8889) - Local inference!
      ↓
Response → Discord chat
```

### 3. Command Processing

```
User types: "!system"
      ↓
Discord → CHROOT_MASTER
      ↓
OpenClaw parses command
      ↓
Executes: bash system_info.sh
      ↓
Returns: System stats
      ↓
Discord displays formatted output
```

## Startup Procedure

### Prerequisites

1. **MiniCPM4 Running**
   ```bash
   # Check if MiniCPM4 is available
   curl http://127.0.0.1:8889/v1/models
   
   # If not running, start it:
   llama-server -m /path/to/minicpm4.gguf --port 8889 -ngl 99
   ```

2. **Termux Environment**
   ```bash
   # Verify proot-distro is installed
   proot-distro list
   
   # Should show: ubuntu
   ```

3. **JARVIS Directory**
   ```bash
   # Check JARVIS exists
   ls ~/JARVIS/node_modules/.bin/clawdbot
   ```

### Start CHROOT_MASTER

```bash
# Method 1: Use the startup script
~/start-chroot-master.sh

# Method 2: Manual start
termux-chroot bash -c '
    cd /data/data/com.termux/files/home/JARVIS
    ./node_modules/.bin/clawdbot gateway run \
        --port 18790 \
        --bind lan
'
```

### Verify Startup

```bash
# Check processes
ps | grep claw

# Check ports
netstat -tlnp | grep 187

# Check logs
tail -f ~/tmp/chroot-master.log

# Test Discord
# Message your bot, should respond!
```

## Capabilities You Now Have

### 🔥 Discord Commands
- `!system` - Get full system info
- `!shell <command>` - Execute any bash command
- `!ls <path>` - List directory contents
- `!read <file>` - Read file contents
- `!write <file> <content>` - Write to file
- `!python <code>` - Execute Python scripts
- `!ps` - List running processes
- `!kill <pid>` - Kill process
- `!find <pattern>` - Search files
- `!network` - Network diagnostics

### 🤖 AI Capabilities
- Local MiniCPM4 inference (no cloud dependency!)
- 200K context window for long conversations
- Real-time responses
- No API costs

### 🛠️ System Access
- Full Linux environment
- Access to Android file system via Termux
- Process management
- Network tools (curl, wget, netstat)
- Development tools (git, npm, python)

## Troubleshooting

### Issue: "Failed to resolve Discord application id"
**Cause**: Invalid Discord token
**Fix**: 
1. Go to https://discord.com/developers/applications
2. Reset bot token
3. Update `~/.config/openclaw/config.json`

### Issue: "No API key found for provider 'farm'"
**Cause**: Missing auth-profiles.json
**Fix**:
```bash
mkdir -p ~/.clawdbot/agents/main/agent
cat > ~/.clawdbot/agents/main/agent/auth-profiles.json << 'EOF'
{
  "farm": {
    "apiKey": "sk-local-farm"
  }
}
EOF
```

### Issue: "Port 18790 in use"
**Cause**: Previous instance still running
**Fix**:
```bash
pkill -9 -f clawdbot
~/start-chroot-master.sh
```

### Issue: "MiniCPM4 not responding"
**Cause**: LLM server not running
**Fix**:
```bash
# Start MiniCPM4 server
llama-server -m /path/to/minicpm4.gguf --port 8889 --host 127.0.0.1 -ngl 99
```

## Performance Optimization

### Memory Management
- Monitor with: `free -h` (in chroot)
- Kill unnecessary processes: `pkill <process>`
- Clear cache: `sync && echo 3 > /proc/sys/vm/drop_caches`

### Model Optimization
- Use `-ngl 99` for full GPU acceleration
- Monitor with: `nvidia-smi` or `clpeak`
- Adjust context window if OOM: 200K → 128K

### Network Optimization
- Check latency: `ping discord.com`
- Verify WebSocket: `curl -I https://gateway.discord.gg`

## Files & Locations

| File | Location | Purpose |
|------|----------|---------|
| Config | `~/.config/openclaw/config.json` | Main CHROOT_MASTER config |
| Auth | `~/.clawdbot/agents/main/agent/auth-profiles.json` | API keys |
| Logs | `~/tmp/chroot-master.log` | Runtime logs |
| Startup | `~/start-chroot-master.sh` | Launch script |
| Workspace | `~/JARVIS` | Working directory |
| Canvas | `~/clawd/canvas` | Browser files |
| LLM | Port 8889 | MiniCPM4 server |

## Next Steps to Maximize

1. ✅ Start CHROOT_MASTER
2. 🔄 Verify Discord connection
3. 🔄 Test MiniCPM4 inference
4. 🔄 Run system diagnostics
5. 🔄 Execute custom commands
6. 🔄 Automate with scripts

## Summary

**CHROOT_MASTER gives you:**
- ✅ Full Discord bot with all commands
- ✅ Local MiniCPM4 inference (200K context)
- ✅ Complete Linux environment
- ✅ No port conflicts with Maclawd
- ✅ Maximum stability and capabilities
- ✅ Zero cloud dependency for AI

**One chroot to rule them all!** 🎉

---
**Last Updated**: 2026-03-08
**Status**: Configuration complete, ready to start
**Architecture**: CHROOT_MASTER v1.0
