# OpenClaw (Clawdbot) Native Installation Guide

This guide walks you through installing OpenClaw (formerly Clawdbot) directly in Termux on your Pixel 8 Pro, connecting it to your Jarvis NPU for fully autonomous operation.

## Prerequisites

- ✅ Pixel 8 Pro with Termux installed
- ✅ Jarvis Android app running (with HTTP API on port 9090)
- ✅ ~500MB free storage
- ✅ Internet connection for downloading packages

## Step 1: Prepare Termux

Open Termux on your Pixel and run:

```bash
# Update packages
pkg update -y
pkg upgrade -y

# Install build dependencies
pkg install -y nodejs git rust python build-essential
```

## Step 2: Get the Setup Script

The setup script has been pushed to `/sdcard/setup_openclaw.sh`. Copy it to Termux:

```bash
# Copy from shared storage to Termux home
cp /sdcard/setup_openclaw.sh ~
cd ~
chmod +x setup_openclaw.sh
```

## Step 3: Run the Setup

```bash
bash setup_openclaw.sh
```

This will:
1. ✅ Install all dependencies (Node.js, Rust, Python, etc.)
2. ✅ Clone the OpenClaw repository
3. ✅ Patch clipboard dependencies for Termux
4. ✅ Build the project

## Step 4: Configure for Jarvis NPU

Create the configuration file:

```bash
mkdir -p ~/.config/openclaw
cat > ~/.config/openclaw/config.json << 'EOF'
{
  "llm": {
    "provider": "openai",
    "baseURL": "http://127.0.0.1:9090/v1",
    "apiKey": "local-jarvis-key",
    "model": "gemma-3b"
  },
  "telegram": {
    "botToken": "8782380079:AAG6RUJT5FXKUs8JG8Nv4cCpvWCpHZPMm0c"
  }
}
EOF
```

## Step 5: Run Onboarding

```bash
cd ~/openclaw
node bin/openclaw onboard
```

Follow the prompts:
- Select **Linux/CLI** environment
- Skip desktop clipboard integration
- Enable Telegram bot (using the token above)

## Step 6: Start the Gateway

In a new Termux session (swipe right and tap "NEW SESSION"):

```bash
cd ~/openclaw
node bin/openclaw gateway --bind 127.0.0.1 --port 18789
```

Leave this running in the background.

## Step 7: Test the Integration

1. Make sure Jarvis is running (tap "START JARVIS" in the app)
2. Open Telegram and message @jarvis2_pixel_bot
3. Try commands like:
   ```
   !system
   !ls /sdcard
   !shell whoami
   ```

## Architecture Overview

```
Telegram (@jarvis2_pixel_bot)
           ↓
OpenClaw Gateway (Termux :18789)
           ↓
Jarvis HTTP API (:9090)
           ↓
Gemma 3B LLM (NPU)
```

## Troubleshooting

### "Permission denied" errors
- Grant Termux storage permission: `termux-setup-storage`
- Re-run setup script

### Clipboard errors
- The clipboard dependency is stubbed - this is expected
- OpenClaw will work fine without it for headless operation

### Gateway won't start
- Check if Jarvis is running: `curl http://127.0.0.1:9090/status`
- Ensure port 18789 is not in use: `netstat -tlnp | grep 18789`

### Build fails
- Make sure you have enough storage: `df -h`
- Try clearing npm cache: `npm cache clean --force`

## Making It Persistent

To keep OpenClaw running after closing Termux:

```bash
# Install termux-services
pkg install termux-services

# Create service
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-openclaw << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
cd ~/openclaw
nohup node bin/openclaw gateway --bind 127.0.0.1 --port 18789 > /dev/null 2>&1 &
EOF

chmod +x ~/.termux/boot/start-openclaw
```

## Full Autonomy Achieved! 🎉

With this setup:
- ✅ LLM runs on Pixel NPU (no cloud dependency)
- ✅ OpenClaw runs in Termux (full Linux environment)
- ✅ Telegram bot for remote access
- ✅ All shell commands available (!shell, !ls, etc.)
- ✅ Python execution capability
- ✅ File management tools

Your Pixel 8 Pro is now a fully autonomous AI server!