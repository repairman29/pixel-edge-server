#!/data/data/com.termux/files/usr/bin/bash
# OpenClaw Setup Script for Termux
# Run this in Termux: bash setup_openclaw.sh

echo "=========================================="
echo "OpenClaw (Clawdbot) Setup for Termux"
echo "=========================================="
echo ""

# Update and install dependencies
echo "[1/6] Updating packages..."
pkg update -y
pkg upgrade -y

echo "[2/6] Installing build dependencies..."
pkg install -y nodejs git rust python build-essential

# Check if already cloned
if [ -d "$HOME/openclaw" ]; then
    echo "OpenClaw directory exists, updating..."
    cd ~/openclaw
    git pull
else
    echo "[3/6] Cloning OpenClaw repository..."
    cd ~
    git clone https://github.com/DriftOS/clawdbot.git openclaw
    cd openclaw
fi

echo "[4/6] Patching clipboard dependency..."
# Find and patch clipboard-rs dependency
if [ -f "package.json" ]; then
    # Check if @mariozechner/clipboard is in dependencies
    if grep -q "@mariozechner/clipboard" package.json; then
        echo "Found clipboard dependency, patching..."
        # Install terminal-clipboard as replacement
        npm install terminal-clipboard --save
        # Create patch for the clipboard module
        mkdir -p patches
        cat > patches/clipboard-stub.js << 'EOF'
// Stub clipboard for Termux/headless environments
module.exports = {
  readText: () => Promise.resolve(''),
  writeText: () => Promise.resolve(),
  readImage: () => Promise.resolve(null),
  writeImage: () => Promise.resolve(),
  readFiles: () => Promise.resolve([]),
  writeFiles: () => Promise.resolve(),
  clear: () => Promise.resolve(),
  watch: () => ({ stop: () => {} })
};
EOF
        echo "✓ Clipboard patched for Termux"
    fi
fi

echo "[5/6] Installing dependencies..."
npm install

echo "[6/6] Building OpenClaw..."
npm run build

echo ""
echo "=========================================="
echo "OpenClaw Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Configure OpenClaw to use Jarvis NPU API:"
echo "   Create ~/.config/openclaw/config.json with:"
echo '   {'
echo '     "llm": {'
echo '       "provider": "openai",'
echo '       "baseURL": "http://127.0.0.1:9090/v1",'
echo '       "apiKey": "local-jarvis-key",'
echo '       "model": "local-npu-model"'
echo '     }'
echo '   }'
echo ""
echo "2. Run onboarding:"
echo "   node bin/openclaw onboard"
echo ""
echo "3. Start gateway:"
echo "   node bin/openclaw gateway --bind 127.0.0.1 --port 18789"