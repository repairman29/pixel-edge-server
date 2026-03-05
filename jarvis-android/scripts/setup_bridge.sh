#!/system/bin/sh
# One-command setup script for Jarvis-Termux bridge
# Run via: adb shell sh /sdcard/jarvis/setup_bridge.sh

echo "================================"
echo "Jarvis Bridge Auto-Setup"
echo "================================"
echo ""

# Check if Termux is installed
if [ ! -d "/data/data/com.termux" ]; then
    echo "❌ Termux not installed!"
    echo ""
    echo "Please install Termux first:"
    echo "  Option 1: Google Play Store"
    echo "  Option 2: F-Droid (recommended)"
    echo "     https://f-droid.org/packages/com.termux/"
    echo ""
    echo "After installing, run this script again."
    exit 1
fi

echo "✓ Termux found"

# Create directories
mkdir -p /sdcard/jarvis/commands
mkdir -p /sdcard/jarvis/results
mkdir -p /sdcard/jarvis/scripts

echo "✓ Directories created"

# Copy bridge script to Termux home
cp /sdcard/jarvis/scripts/termux_bridge.py /data/data/com.termux/files/home/jarvis_bridge.py 2>/dev/null

if [ -f "/data/data/com.termux/files/home/jarvis_bridge.py" ]; then
    echo "✓ Bridge script copied to Termux"
    echo ""
    echo "================================"
    echo "Setup complete! Next steps:"
    echo "================================"
    echo ""
    echo "1. Open Termux app"
    echo "2. Run these commands:"
    echo ""
    echo "   echo 'allow-external-apps = true' >> ~/.termux/termux.properties"
    echo "   termux-reload-settings"
    echo "   pkg update && pkg install python -y"
    echo "   python3 ~/jarvis_bridge.py"
    echo ""
    echo "3. Start Jarvis app and send commands via Telegram:"
    echo "   !shell ls -la"
    echo "   !system"
    echo "   !ping google.com"
    echo ""
else
    echo "❌ Failed to copy bridge script"
    echo "Make sure Jarvis APK was installed first"
fi