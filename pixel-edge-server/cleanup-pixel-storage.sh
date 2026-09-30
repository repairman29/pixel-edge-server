#!/bin/bash
# Cleanup Pixel storage - run from Mac with device connected via ADB
# Frees ~2–3 GB by removing duplicates and caches
# Usage: ./cleanup-pixel-storage.sh [--yes]  # --yes = skip prompts, delete all

set -e
AUTO_YES=false
[[ "$1" == "--yes" ]] && AUTO_YES=true

ask() { [[ "$AUTO_YES" == true ]] && return 0; read -p "   $1 [y/N] " r; [[ "$r" =~ ^[yY] ]]; }

echo "=========================================="
echo "Pixel Storage Cleanup"
echo "=========================================="
echo ""

if ! adb devices | grep -q "device$"; then
    echo "❌ No device connected. Connect Pixel via USB."
    exit 1
fi

echo "Current storage:"
adb shell df -h /data | grep -E "Filesystem|/data"
echo ""

# --- 1. Download folder (sdcard) ---
echo "1. Download folder (sdcard)"
echo "   JARVIS.tar.gz (~880 MB) - duplicate of Termux copy"
if ask "Delete Download/JARVIS.tar.gz?"; then
    adb shell rm -f /storage/emulated/0/Download/JARVIS.tar.gz
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

# --- 2. jarvis-android.tar.gz on sdcard ---
echo ""
echo "2. jarvis-android.tar.gz on sdcard (~98 MB) - you have it in repo"
if ask "Delete?"; then
    adb shell rm -f /storage/emulated/0/jarvis-android.tar.gz
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

# --- 3. jarvis-build on sdcard ---
echo ""
echo "3. jarvis-build on sdcard (~127 MB) - build artifacts"
if ask "Delete?"; then
    adb shell rm -rf /storage/emulated/0/jarvis-build
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

# --- 4. Termux: JARVIS.tar.gz (keep extracted JARVIS dir) ---
echo ""
echo "4. Termux: ~/JARVIS.tar.gz (~878 MB) - archive, JARVIS dir already extracted"
if ask "Delete from Termux?"; then
    adb shell "run-as com.termux rm -f /data/data/com.termux/files/home/JARVIS.tar.gz"
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

# --- 5. Termux: neural-farm.tar.gz ---
echo ""
echo "5. Termux: ~/neural-farm.tar.gz (~30 MB) - archive, neural-farm dir exists"
if ask "Delete from Termux?"; then
    adb shell "run-as com.termux rm -f /data/data/com.termux/files/home/neural-farm.tar.gz"
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

# --- 6. Termux: npm cache ---
echo ""
echo "6. Termux: ~/.npm cache (~624 MB)"
if ask "Clear npm cache?"; then
    adb shell "run-as com.termux npm cache clean --force 2>/dev/null || true"
    adb shell "run-as com.termux rm -rf /data/data/com.termux/files/home/.npm/_cacache 2>/dev/null || true"
    echo "   ✓ Cleared"
else
    echo "   Skipped"
fi

# --- 7. Termux: old logs ---
echo ""
echo "7. Termux: old *.log files"
if ask "Delete log files?"; then
    adb shell "run-as com.termux sh -c 'cd /data/data/com.termux/files/home && rm -f *.log 2>/dev/null'"
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

# --- 8. Duplicate scripts on sdcard root ---
echo ""
echo "8. Duplicate scripts on sdcard root (setup_openclaw.sh, fix-gateway.sh, etc.)"
if ask "Delete?"; then
    for f in setup_openclaw.sh run-gateway-android.sh start-gateway-fixed.sh start-gateway-final.sh \
             patch-and-start.sh fix-gateway.sh gateway-android-fix.sh openclaw_install.sh \
             jarvis-setup-android16.sh patch-source.sh run-full-jarvis.sh ultimate-fix.sh \
             test-telegram.sh test-telegram-node.js test-gateway-chat.js test.c \
             termux-setup-cpu.sh termux-jarvis-setup.sh; do
        adb shell "rm -f /storage/emulated/0/$f" 2>/dev/null || true
    done
    echo "   ✓ Deleted"
else
    echo "   Skipped"
fi

echo ""
echo "=========================================="
echo "Done. New storage:"
adb shell df -h /data | grep -E "Filesystem|/data"
echo ""
echo "Optional: Clear app caches in Settings > Apps > [app] > Storage > Clear cache"
echo "Optional: Uninstall unused apps"
