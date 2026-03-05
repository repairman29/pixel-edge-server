#!/bin/bash
# Setup script for Jarvis-Termux integration
# Run this in Termux: bash setup_jarvis_bridge.sh

echo "================================"
echo "Jarvis-Termux Bridge Setup"
echo "================================"
echo ""

# Update packages
echo "Updating packages..."
pkg update -y

# Install Python if not present
echo "Installing Python..."
pkg install -y python

# Install required Python packages
echo "Installing Python packages..."
pip install --upgrade pip

# Create directories
echo "Creating directories..."
mkdir -p /sdcard/jarvis/commands
mkdir -p /sdcard/jarvis/results
mkdir -p /sdcard/jarvis/scripts

# Check if allow-external-apps is set
echo ""
echo "Checking Termux configuration..."
if ! grep -q "allow-external-apps = true" ~/.termux/termux.properties 2>/dev/null; then
    echo "⚠️  WARNING: You need to enable external apps access!"
    echo ""
    echo "Please run these commands:"
    echo "  echo 'allow-external-apps = true' >> ~/.termux/termux.properties"
    echo "  termux-reload-settings"
    echo ""
    echo "Or manually:"
    echo "  1. nano ~/.termux/termux.properties"
    echo "  2. Add: allow-external-apps = true"
    echo "  3. Save and exit"
    echo "  4. Restart Termux"
else
    echo "✓ External apps access already enabled"
fi

# Copy bridge script
echo ""
echo "Setting up bridge script..."
if [ -f "/sdcard/jarvis/scripts/termux_bridge.py" ]; then
    cp /sdcard/jarvis/scripts/termux_bridge.py ~/jarvis_bridge.py
    chmod +x ~/jarvis_bridge.py
    echo "✓ Bridge script copied"
else
    echo "⚠️  Bridge script not found in /sdcard/jarvis/scripts/"
    echo "Please copy termux_bridge.py to Termux home directory manually"
fi

echo ""
echo "================================"
echo "Setup complete!"
echo "================================"
echo ""
echo "To start the bridge:"
echo "  cd ~"
echo "  python3 jarvis_bridge.py"
echo ""
echo "The bridge will run continuously and wait for commands from Jarvis."
echo ""