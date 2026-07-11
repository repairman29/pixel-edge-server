#!/bin/bash
# ONE-LINER: Setup OpenClaw on Pixel via ADB
# Run this on Mac: bash ONE_LINER_SETUP.sh

echo "========================================="
echo "OpenClaw One-Click Setup"
echo "========================================="
echo ""

# Check ADB connection
if ! adb devices | grep -q "device$"; then
    echo "❌ Error: No device connected via ADB"
    echo "Connect your Pixel with USB debugging enabled"
    exit 1
fi

echo "✓ Device connected"

# Create installation script on Mac side (to avoid escape issues)
cat > /tmp/openclaw_install.sh << 'TERMUX_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~
echo "=== OpenClaw Installation Starting ==="

# Update packages
pkg update -y

# Install dependencies
pkg install -y nodejs-lts git rust python build-essential

# Clone or update OpenClaw
if [ -d "openclaw" ]; then
    echo "Updating existing installation..."
    cd openclaw
    git fetch origin
    git pull
else
    echo "Cloning OpenClaw..."
    git clone https://github.com/DriftOS/clawdbot.git openclaw
    cd openclaw
fi

# Create clipboard stub
echo "Patching clipboard for Android..."
mkdir -p node_modules/@mariozechner/clipboard
cat > node_modules/@mariozechner/clipboard/index.js << 'CLIPBOARD_EOF'
class Clipboard {
  async readText() { return ''; }
  async writeText(text) { 
    try { 
      require('child_process').execSync(`termux-clipboard-set '${text.replace(/'/g, "'\\''")}' 2>/dev/null`); 
    } catch(e) {}
    return true; 
  }
  async readImage() { return null; }
  async writeImage() { }
  async readFiles() { return []; }
  async writeFiles() { }
  async clear() { }
  watch() { return { stop: () => {} }; }
}
module.exports = { Clipboard };
CLIPBOARD_EOF

# Create package.json for stub
cat > node_modules/@mariozechner/clipboard/package.json << 'JSON_EOF'
{"name": "@mariozechner/clipboard", "version": "0.0.0-stub", "main": "index.js"}
JSON_EOF

# Install and build
echo "Installing dependencies..."
npm install --legacy-peer-deps 2>&1 | tail -10

echo "Building OpenClaw..."
npm run build 2>&1 | tail -20

# Create config
mkdir -p ~/.config/openclaw
cat > ~/.config/openclaw/config.json << 'CONFIG_EOF'
{
  "llm": {
    "provider": "openai",
    "baseURL": "http://127.0.0.1:9090/v1",
    "apiKey": "local",
    "model": "gemma-3b"
  },
  "telegram": {
    "enabled": true,
    "botToken": "REPLACE_WITH_YOUR_TELEGRAM_BOT_TOKEN"
  }
}
CONFIG_EOF

# Create start script
cat > ~/start-openclaw.sh << 'START_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/openclaw
nohup node bin/openclaw gateway --bind 127.0.0.1 --port 18789 > /sdcard/openclaw.log 2>&1 &
echo "OpenClaw started! Check: tail -f /sdcard/openclaw.log"
START_EOF
chmod +x ~/start-openclaw.sh

echo ""
echo "=== Installation Complete ==="
echo "1. Start Jarvis app on your phone"
echo "2. Tap START JARVIS"
echo "3. Then run: ~/start-openclaw.sh"
echo ""
echo "Message @jarvis2_pixel_bot when ready!"
TERMUX_EOF

# Push to device
adb push /tmp/openclaw_install.sh /sdcard/

# Open Termux and run installation
adb shell am start -a android.intent.action.MAIN -n com.termux/.app.TermuxActivity
echo ""
echo "✓ Termux opened"
echo ""
echo "NEXT STEPS (run in Termux):"
echo "1. Copy: cp /sdcard/openclaw_install.sh ~"
echo "2. Run: bash ~/openclaw_install.sh"
echo "3. Wait 20-40 minutes"
echo ""
echo "Then start Jarvis and message @jarvis2_pixel_bot"