#!/bin/bash
# start-gateway.sh — Mac-side launcher
# Dispatches the gateway startup script to the Pixel via ADB.
# Requires: adb connected (USB or WiFi), Termux installed on Pixel.

set -e

TERMUX_HOME="/data/data/com.termux/files/home"
GATEWAY_SCRIPT="$TERMUX_HOME/start-gateway.sh"

echo "=== Jarvis Gateway — Mac Launcher ==="
echo ""

# Check ADB device connected
if ! adb devices | grep -q "device$"; then
    echo "ERROR: No ADB device found. Connect Pixel via USB and enable USB debugging."
    exit 1
fi
echo "✓ ADB device connected"

# Verify the script is present on device
if ! adb shell "run-as com.termux test -f $GATEWAY_SCRIPT" 2>/dev/null; then
    echo "ERROR: $GATEWAY_SCRIPT not found on device."
    echo "Run setup first, or check pixel-edge-server/MAKE_IT_WORK.md"
    exit 1
fi

echo "Launching gateway on Pixel..."
echo "(Output will stream here. Ctrl+C to detach — gateway keeps running on device)"
echo ""

# Run in Termux environment via adb shell
adb shell "run-as com.termux $TERMUX_HOME/start-gateway.sh"
