# Jarvis-Termux Bridge

This integration allows Jarvis to execute commands in Termux, giving it access to the full Linux environment, Python, Node.js, and all Termux packages.

## Architecture

```
Jarvis (Android)  <--->  Shared Files  <--->  Termux (Linux)
  Kotlin                /sdcard/jarvis/      Python
  TermuxBridge          commands/            Bridge Script
                        results/
```

## Setup Instructions

### 1. Install Termux

From Play Store or F-Droid:
```
https://f-d.google.com/packages/com.termux
```

### 2. Configure Termux

Open Termux and run:
```bash
# Enable external app access
echo 'allow-external-apps = true' >> ~/.termux/termux.properties
termux-reload-settings

# Install Python
pkg update
pkg install python -y

# Optional: Install useful packages
pkg install nodejs git vim nano -y
```

### 3. Copy Bridge Script

From your Mac (with device connected):
```bash
adb push /Users/jeffadkins/Projects/jarvis-android/scripts/termux_bridge.py /sdcard/jarvis/scripts/
```

Or in Termux:
```bash
# Download the script
curl -o ~/jarvis_bridge.py [URL_TO_SCRIPT]
```

### 4. Start the Bridge

In Termux:
```bash
cd ~
python3 jarvis_bridge.py
```

You should see:
```
==================================================
Jarvis-Termux Bridge Starting...
Command dir: /sdcard/jarvis/commands
Result dir: /sdcard/jarvis/results
==================================================
```

## Usage from Jarvis

Once the bridge is running, you can use these commands in Telegram:

### Execute Shell Commands
```
!shell ls -la /sdcard
!shell df -h
!shell ps aux
```

### Read Files
```
!read /sdcard/somefile.txt
```

### Write Files
```
!write /sdcard/test.txt Hello from Jarvis!
```

### List Directory
```
!ls /sdcard
```

### System Info
```
!system
```

### Run Python
```
!python print("Hello World")
```

### Ping
```
!ping google.com
```

## How It Works

1. **Jarvis sends command**: Writes a JSON file to `/sdcard/jarvis/commands/[uuid].json`
2. **Bridge detects**: Python script watches directory using polling
3. **Bridge executes**: Runs the command in Termux environment
4. **Bridge responds**: Writes result to `/sdcard/jarvis/results/[uuid].json`
5. **Jarvis reads**: Kotlin code polls for result and returns it to user

## Security Notes

- Commands run with Termux user permissions (not root)
- Bridge only executes commands from JSON files it finds
- No network access required - all communication via filesystem
- Results are cleaned up after reading

## Troubleshooting

### "allow-external-apps not set"
Make sure you ran:
```bash
echo 'allow-external-apps = true' >> ~/.termux/termux.properties
termux-reload-settings
```
Then restart Termux completely.

### Bridge not responding
Check if bridge is running:
```bash
ps aux | grep jarvis_bridge
```

Check logs:
```bash
tail -f /sdcard/jarvis/bridge.log
```

### Permission denied
Ensure Jarvis has storage permissions in Android settings.

## Advanced Usage

### Custom Commands

You can extend the Python bridge to add custom command types. Edit `jarvis_bridge.py` and add new handlers in the `process_command` function.

### Background Services

To keep bridge running:
```bash
# Install termux-services
pkg install termux-services -y

# Create service
mkdir -p ~/.termux/boot
cp jarvis_bridge.py ~/.termux/boot/
```

### Integration with Shizuku

If you have Shizuku running, you can also use `rish` within Termux for elevated commands:
```python
# In bridge script
if command.get("elevated"):
    full_cmd = f"rish -c '{command['params']['command']}'"
```

## Files Created

- `/sdcard/jarvis/commands/` - Command files from Jarvis
- `/sdcard/jarvis/results/` - Result files from Termux
- `/sdcard/jarvis/bridge.log` - Bridge execution log
- `~/jarvis_bridge.py` - The bridge script (in Termux home)