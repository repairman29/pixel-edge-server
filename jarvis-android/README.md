# 🤖 JARVIS - Android Edge AI Assistant

A fully autonomous AI assistant running on Google Pixel 8 Pro using on-device LLM (Gemma 3B) with Telegram integration and Termux bridge for full Linux command execution.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Telegram      │────▶│  Jarvis Android  │────▶│   Gemma 3B      │
│   @eljarvo_bot  │◀────│  (Pixel 8 Pro)   │◀────│   (NPU/CPU)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │   Termux Bridge  │
                        │   (Linux/SSH)    │
                        └──────────────────┘
```

## Components

### 1. Android App (`com.d6.jarvis`)
- **LlmEngine**: Loads and runs Gemma 3B model on NPU/CPU
- **TelegramBot**: Handles messaging via @eljarvo_bot
- **JarvisService**: Foreground service keeping everything alive
- **TermuxBridge**: SSH-based command execution bridge
- **HttpApiServer**: REST API on port 9090

### 2. Termux Bridge (`jarvis_bridge.py`)
- Listens for commands via SSH or file-based IPC
- Executes shell commands, Python scripts, file operations
- Returns JSON results to Android app

### 3. Model
- **Model**: Gemma 3 1B IT (Int4 quantized, ~529MB)
- **Location**: `/data/local/tmp/llm/model.task`
- **Backend**: CPU with XNNPACK acceleration

## Quick Start

### Prerequisites
- Google Pixel 8 Pro (Android 16)
- Termux installed from F-Droid
- Telegram bot token (@eljarvo_bot: `8757734547:AAE...`)

### Installation

```bash
# 1. Install APK
adb install -r app-debug.apk

# 2. Push model (from Mac)
curl -L -H "Authorization: Bearer <HF_TOKEN>" \
  -o gemma3-1b-it-int4.task \
  "https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task"
adb shell mkdir -p /data/local/tmp/llm
adb push gemma3-1b-it-int4.task /data/local/tmp/llm/model.task

# 3. Start app
adb shell am start -n com.d6.jarvis/.MainActivity

# 4. Tap "START JARVIS" in UI
```

### Termux Setup (One-Time)

```bash
# In Termux:
pkg update && pkg install openssh python -y

# Configure SSH
echo 'allow-external-apps = true' >> ~/.termux/termux.properties
termux-reload-settings
sshd

# Add authorized key
mkdir -p ~/.ssh
cat /sdcard/jarvis/termux_pixel.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Start bridge
cp /sdcard/jarvis/scripts/termux_bridge.py ~/jarvis_bridge.py
python3 ~/jarvis_bridge.py
```

## Usage

### Telegram Commands

| Command | Description | Example |
|---------|-------------|---------|
| `!shell <cmd>` | Execute shell command | `!shell ls -la /sdcard` |
| `!ls <path>` | List directory | `!ls /sdcard/Download` |
| `!system` | Get system info | `!system` |
| `!ping <host>` | Ping host | `!ping google.com` |
| `!python <code>` | Run Python | `!python print(2+2)` |
| `!read <file>` | Read file | `!read /sdcard/file.txt` |
| `/status` | Check Jarvis status | `/status` |
| `/model` | Check model status | `/model` |

### HTTP API (Port 9090)

```bash
# Status
curl http://localhost:9090/status

# Inference
curl -X POST http://localhost:9090/infer \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello, who are you?"}'

# OpenAI-compatible
curl -X POST http://localhost:9090/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}],
    "model": "gemma-3b"
  }'
```

### SSH Access

```bash
# Forward port via ADB
adb forward tcp:8022 tcp:8022

# Connect
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1

# Or direct commands
ssh -p 8022 -i ~/.ssh/termux_pixel termux@127.0.0.1 'ls -la /sdcard'
```

## File Structure

```
/sdcard/jarvis/
├── commands/           # Command JSONs from Jarvis
├── results/            # Result JSONs from Termux
├── scripts/
│   ├── termux_bridge.py
│   ├── setup_ssh.sh
│   └── setup_bridge.sh
├── SETUP.md
├── SSH_SETUP.md
└── TERMUX_BRIDGE.md
```

## Development

### Building

```bash
cd jarvis-android/
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew assembleDebug
```

### Key Files

| File | Purpose |
|------|---------|
| `LlmEngine.kt` | LLM inference engine |
| `TelegramBot.kt` | Telegram bot polling |
| `JarvisService.kt` | Main service orchestrator |
| `TermuxBridge.kt` | SSH/command bridge |
| `ToolManager.kt` | Android tool execution |
| `HttpApiServer.kt` | HTTP REST API |

## Troubleshooting

### "Model not loaded"
```bash
# Check model exists
adb shell ls -la /data/local/tmp/llm/model.task

# Re-push if missing
adb push gemma3-1b-it-int4.task /data/local/tmp/llm/model.task
```

### "Telegram not connected"
- Check internet connectivity
- Verify bot token is correct
- Check logs: `adb logcat -s TelegramBot`

### SSH Connection Issues
```bash
# Check SSH is running
adb shell "ps -A | grep sshd"

# Restart SSH
adb shell "killall sshd 2>/dev/null; sshd"

# Forward port
adb forward tcp:8022 tcp:8022
```

### Bridge Not Responding
```bash
# Check if running
ssh -p 8022 termux@127.0.0.1 'ps aux | grep jarvis_bridge'

# Restart bridge
ssh -p 8022 termux@127.0.0.1 'pkill -f jarvis_bridge; python3 ~/jarvis_bridge.py'

# Check logs
ssh -p 8022 termux@127.0.0.1 'tail -20 /sdcard/jarvis/bridge.log'
```

## Technical Details

### Model
- **Type**: Gemma 3 1B IT Int4
- **Size**: 529MB
- **Backend**: CPU (XNNPACK)
- **Quantization**: Dynamic Int4
- **Source**: [HuggingFace](https://huggingface.co/litert-community/Gemma3-1B-IT)

### Performance
- Model Load: ~2 seconds
- Inference: ~50-100 tokens/second
- Memory: ~1.5GB peak
- Battery: Optimized with wake lock

### Architecture
- **Language**: Kotlin (Android), Python (Termux)
- **HTTP**: NanoHTTPD
- **HTTP Client**: OkHttp3
- **JSON**: org.json
- **Concurrency**: Kotlin Coroutines

## Security Notes

- SSH keys stored in `~/.ssh/` (Termux) and `~/.ssh/` (Mac)
- No password authentication (key-based only)
- Termux runs as non-root user
- All file access via `/sdcard/` (shared storage)
- Telegram bot token in code (for development)

## License

GNU AGPLv3 - See LICENSE file

## Credits

- **Gemma Model**: Google
- **MediaPipe**: Google AI Edge
- **Termux**: Fredrik Fornwall
- **Telegram Bot**: Telegram MTProto API