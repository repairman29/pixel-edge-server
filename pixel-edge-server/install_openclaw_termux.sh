#!/data/data/com.termux/files/usr/bin/bash
# Real OpenClaw Installation for Termux
# This script installs and patches Clawdbot to work on Android

set -e  # Exit on error

echo "=========================================="
echo "OpenClaw (Clawdbot) Native Install"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Step 1: Environment Setup
log_info "Step 1/7: Setting up environment..."
pkg update -y
pkg install -y nodejs-lts git rust python build-essential curl wget

# Ensure we're in home directory
cd ~

# Step 2: Clone OpenClaw
log_info "Step 2/7: Cloning OpenClaw repository..."
if [ -d "openclaw" ]; then
    log_warn "Directory exists, updating..."
    cd openclaw
    git fetch origin
    git reset --hard origin/main || git pull
else
    git clone https://github.com/DriftOS/clawdbot.git openclaw
    cd openclaw
fi

# Step 3: Patch for Termux (Critical)
log_info "Step 3/7: Patching for Termux compatibility..."

# Find and patch clipboard dependency
if grep -q "@mariozechner/clipboard" package.json 2>/dev/null; then
    log_info "Found clipboard dependency, patching..."
    
    # Create a stub module
    mkdir -p node_modules/@mariozechner/clipboard
    cat > node_modules/@mariozechner/clipboard/index.js << 'EOF'
// Stub clipboard for Termux/Android (headless)
const { execSync } = require('child_process');

class Clipboard {
  async readText() {
    try {
      // Try to use termux-clipboard-get if available
      return execSync('termux-clipboard-get 2>/dev/null || echo ""', { encoding: 'utf8' }).trim();
    } catch (e) {
      return '';
    }
  }
  
  async writeText(text) {
    try {
      // Try to use termux-clipboard-set if available
      const escaped = text.replace(/'/g, "'\\''");
      execSync(`termux-clipboard-set '${escaped}' 2>/dev/null || echo "clipboard not available"`, { encoding: 'utf8' });
      return true;
    } catch (e) {
      console.log('Clipboard write not available (headless mode)');
      return false;
    }
  }
  
  async readImage() { return null; }
  async writeImage() { return; }
  async readFiles() { return []; }
  async writeFiles() { return; }
  async clear() { return; }
  watch() { return { stop: () => {} }; }
}

module.exports = { Clipboard };
EOF

    # Create package.json for stub
    cat > node_modules/@mariozechner/clipboard/package.json << 'EOF'
{
  "name": "@mariozechner/clipboard",
  "version": "0.0.0-stub",
  "main": "index.js",
  "types": "index.d.ts"
}
EOF

    # Create TypeScript definitions
    cat > node_modules/@mariozechner/clipboard/index.d.ts << 'EOF'
export declare class Clipboard {
  readText(): Promise<string>;
  writeText(text: string): Promise<boolean>;
  readImage(): Promise<null>;
  writeImage(): Promise<void>;
  readFiles(): Promise<[]>;
  writeFiles(): Promise<void>;
  clear(): Promise<void>;
  watch(): { stop: () => void };
}
EOF

    log_info "✓ Clipboard patched for Termux"
fi

# Step 4: Install Dependencies
log_info "Step 4/7: Installing npm dependencies..."
npm install --legacy-peer-deps 2>&1 | tail -20

# Step 5: Build
log_info "Step 5/7: Building OpenClaw..."
npm run build 2>&1 | tail -30

if [ ! -f "bin/clawdbot" ] && [ ! -f "bin/openclaw" ]; then
    log_error "Build failed - binary not found"
    exit 1
fi

# Step 6: Create Config
log_info "Step 6/7: Creating configuration..."
mkdir -p ~/.config/openclaw

# Detect Jarvis API
JARVIS_API="http://127.0.0.1:9090/v1"

# Get Telegram token from user or use default
TELEGRAM_TOKEN="${1:-${TELEGRAM_BOT_TOKEN:?Provide the Telegram bot token as arg 1 or via the TELEGRAM_BOT_TOKEN env var}}"

cat > ~/.config/openclaw/config.json << EOF
{
  "llm": {
    "provider": "openai",
    "baseURL": "$JARVIS_API",
    "apiKey": "local-pixel-npu",
    "model": "gemma-3b-it",
    "maxTokens": 1024
  },
  "telegram": {
    "enabled": true,
    "botToken": "$TELEGRAM_TOKEN"
  },
  "system": {
    "autoUpdate": false,
    "headless": true,
    "workingDirectory": "/data/data/com.termux/files/home"
  },
  "tools": {
    "shell": true,
    "file": true,
    "process": true,
    "network": true
  }
}
EOF

log_info "✓ Configuration created at ~/.config/openclaw/config.json"

# Step 7: Create startup scripts
log_info "Step 7/7: Creating startup scripts..."

# Start script
cat > ~/start-openclaw.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/openclaw
echo "Starting OpenClaw Gateway..."
nohup node bin/openclaw gateway --bind 127.0.0.1 --port 18789 > /sdcard/openclaw.log 2>&1 &
echo "✓ OpenClaw started on port 18789"
echo "View logs: tail -f /sdcard/openclaw.log"
EOF
chmod +x ~/start-openclaw.sh

# Stop script
cat > ~/stop-openclaw.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "openclaw gateway" || echo "OpenClaw not running"
echo "✓ OpenClaw stopped"
EOF
chmod +x ~/stop-openclaw.sh

# Status script
cat > ~/status-openclaw.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
if pgrep -f "openclaw gateway" > /dev/null; then
    echo "✓ OpenClaw is running"
    tail -10 /sdcard/openclaw.log
else
    echo "✗ OpenClaw is not running"
fi
EOF
chmod +x ~/status-openclaw.sh

# Create service for auto-start
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/openclaw << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Auto-start OpenClaw on boot
if [ -f ~/openclaw/bin/openclaw ]; then
    cd ~/openclaw
    nohup node bin/openclaw gateway --bind 127.0.0.1 --port 18789 > /sdcard/openclaw.log 2>&1 &
fi
EOF
chmod +x ~/.termux/boot/openclaw

echo ""
echo "=========================================="
echo "✓ OpenClaw Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Start OpenClaw: ~/start-openclaw.sh"
echo "2. Check status: ~/status-openclaw.sh"
echo "3. Stop OpenClaw: ~/stop-openclaw.sh"
echo "4. View logs: tail -f /sdcard/openclaw.log"
echo ""
echo "Make sure Jarvis is running first (for LLM access)"
echo "Then message your bot on Telegram!"