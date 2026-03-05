# Jarvis-Termux Setup Guide

## Quick Setup (Minimal Steps)

### Step 1: Install Termux (2 minutes)
On your Pixel 8 Pro:
1. Open Chrome
2. Go to: https://f-droid.org/packages/com.termux/
3. Download and install Termux
4. Open Termux app (it will ask for storage permission - ALLOW)

### Step 2: Run Setup Script (1 minute)
In Termux, paste this:
```bash
echo 'allow-external-apps = true' >> ~/.termux/termux.properties && termux-reload-settings && pkg update && pkg install python -y && curl -o ~/jarvis_bridge.py https://raw.githubusercontent.com/repairman29/jarvis-android/main/scripts/termux_bridge.py && python3 ~/jarvis_bridge.py
```

**That's it!** The bridge is now running.

### Step 3: Start Jarvis
1. Open Jarvis app on Pixel
2. Tap "START JARVIS"
3. Send commands via Telegram @eljarvo_bot

## Available Commands

Once running, send these in Telegram:

```
!shell ls -la                    # List files
!shell df -h                     # Disk usage  
!shell ps aux                    # Running processes
!system                          # System info
!ping google.com                 # Ping test
!ls /sdcard                      # List sdcard
!python print("Hello")           # Run Python
!read /sdcard/file.txt          # Read file
```

## Full Setup (Recommended)

### 1. Install Termux
Download from F-Droid (more stable than Play Store):
```
https://f-droid.org/packages/com.termux/
```

### 2. Configure Permissions
Open Termux and run:
```bash
# Allow external apps to send commands
echo 'allow-external-apps = true' >> ~/.termux/termux.properties
termux-reload-settings

# Grant storage permission (will prompt)
termux-setup-storage
```

### 3. Install Python
```bash
pkg update
pkg install python -y
```

### 4. Download Bridge Script
```bash
# Option A: From this repo
cp /sdcard/jarvis/scripts/termux_bridge.py ~/jarvis_bridge.py

# Option B: Download from GitHub
curl -o ~/jarvis_bridge.py https://raw.githubusercontent.com/repairman29/jarvis-android/main/scripts/termux_bridge.py
```

### 5. Start Bridge
```bash
python3 ~/jarvis_bridge.py
```

You should see:
```
==================================================
Jarvis-Termux Bridge Starting...
Command dir: /sdcard/jarvis/commands
Result dir: /sdcard/jarvis/results
==================================================
```

## Troubleshooting

### "Permission denied" error
Run in Termux:
```bash
echo 'allow-external-apps = true' >> ~/.termux/termux.properties
termux-reload-settings
# Restart Termux completely
```

### "python: command not found"
```bash
pkg install python -y
```

### "No such file or directory"
Check if directories exist:
```bash
ls -la /sdcard/jarvis/
```
If missing:
```bash
mkdir -p /sdcard/jarvis/commands /sdcard/jarvis/results
```

### Bridge not responding
1. Check if running:
```bash
ps aux | grep jarvis
```

2. Check logs:
```bash
tail -f /sdcard/jarvis/bridge.log
```

3. Restart bridge:
```bash
# Kill existing
pkill -f jarvis_bridge

# Start again
python3 ~/jarvis_bridge.py
```

### Jarvis says "Timeout"
- Make sure bridge is running in Termux
- Check that Termux has storage permission
- Try restarting both Jarvis and Termux bridge

## Advanced Usage

### Run Bridge in Background
```bash
# Install termux-api
pkg install termux-api

# Run with nohup
nohup python3 ~/jarvis_bridge.py > /dev/null 2>&1 &

# Check if running
ps aux | grep jarvis
```

### Auto-start on Boot
```bash
# Install termux-services
pkg install termux-services

# Create service
mkdir -p ~/.termux/boot
cp ~/jarvis_bridge.py ~/.termux/boot/

# Make executable
chmod +x ~/.termux/boot/jarvis_bridge.py
```

### Custom Commands
Edit `~/jarvis_bridge.py` and add new command types:

```python
elif cmd_type == "my_custom":
    result = do_something(params)
```

## Architecture

```
Telegram → Jarvis → JSON → /sdcard/jarvis/commands/
                                         ↓
                              Python Bridge Script
                                         ↓
                              /sdcard/jarvis/results/
                                         ↓
                              Jarvis → Telegram
```

- No network required
- All communication via filesystem
- Secure (Termux user permissions)
- Fast (<1s response time)

## Support

If stuck:
1. Check bridge logs: `tail /sdcard/jarvis/bridge.log`
2. Verify Termux setup: `cat ~/.termux/termux.properties`
3. Restart everything: Kill Termux and Jarvis, start fresh