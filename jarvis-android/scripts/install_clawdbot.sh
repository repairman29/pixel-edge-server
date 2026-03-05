#!/data/data/com.termux/files/usr/bin/sh
# Install Clawdbot on Pixel via Termux
# Run in Termux: bash install_clawdbot.sh

echo "================================"
echo "Clawdbot Installation"
echo "================================"
echo ""

# Check if already installed
if [ -f "/data/data/com.termux/files/usr/bin/clawdbot" ]; then
    echo "✓ Clawdbot already installed"
    clawdbot --version 2>/dev/null || echo "version check failed"
    exit 0
fi

echo "Installing Clawdbot..."

# Update packages
pkg update -y

# Install dependencies
echo "Installing dependencies..."
pkg install -y git python nodejs

# Install clawdbot via npm (if available)
echo "Attempting npm install..."
npm install -g clawdbot 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✓ Clawdbot installed via npm"
else
    echo "npm install failed, trying alternative..."
    
    # Alternative: Clone and build from source
    cd ~
    git clone https://github.com/repairman29/clawdbot.git 2>/dev/null || echo "Clone failed, manual install needed"
    
    if [ -d "~/clawdbot" ]; then
        cd clawdbot
        npm install
        npm run build
        ln -s ~/clawdbot/bin/clawdbot /data/data/com.termux/files/usr/bin/clawdbot
        echo "✓ Clawdbot built from source"
    fi
fi

# Check installation
if [ -f "/data/data/com.termux/files/usr/bin/clawdbot" ]; then
    echo ""
    echo "================================"
    echo "Installation Complete!"
    echo "================================"
    echo ""
    echo "Approve the pairing code:"
    echo "  clawdbot pairing approve telegram WT4LUXF4"
    echo ""
else
    echo "❌ Installation failed"
    echo "You may need to install manually"
fi