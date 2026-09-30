#!/usr/bin/env bash
# Phase 1 setup via ADB: phantom bypass + Termux (+ optional Termux:API).
# Requires: Pixel connected, USB debugging on. Optional: allow "Install via USB" if installs fail.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APKS="$SCRIPT_DIR/apks"
cd "$SCRIPT_DIR/.."

if ! command -v adb &>/dev/null; then
  echo "adb not found. Install Android platform tools."
  exit 1
fi
if ! adb devices | grep -q 'device$'; then
  echo "No device connected. Enable USB debugging and connect the Pixel."
  exit 1
fi

echo "=== 1. Phantom process bypass ==="
"$SCRIPT_DIR/phantom_bypass.sh"

echo ""
echo "=== 2. Termux ==="
mkdir -p "$APKS"
if [[ ! -f "$APKS/termux_arm64.apk" ]]; then
  echo "Downloading Termux (GitHub, arm64)..."
  curl -sL -o "$APKS/termux_arm64.apk" \
    "https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_arm64-v8a.apk"
fi
if adb install -r -t "$APKS/termux_arm64.apk" 2>/dev/null; then
  echo "Termux installed via ADB."
else
  echo "Pushing APK to device Download folder; install from the phone."
  adb push "$APKS/termux_arm64.apk" /sdcard/Download/termux_arm64.apk
  echo "On the Pixel: Files → Download → termux_arm64.apk → Install. See scripts/INSTALL_TERMUX.md"
fi

echo ""
echo "=== 3. Termux:API (same signer as Termux) ==="
if [[ ! -f "$APKS/termux-api.apk" ]]; then
  echo "Downloading Termux:API (F-Droid)..."
  curl -sL -o "$APKS/termux-api.apk" "https://f-droid.org/repo/com.termux.api_1002.apk"
fi
if adb install -r "$APKS/termux-api.apk" 2>/dev/null; then
  echo "Termux:API installed."
else
  echo "Termux:API install failed (GitHub Termux has different signer than F-Droid API)."
  echo "On the Pixel: install F-Droid, then install both Termux and Termux:API from F-Droid."
fi

echo ""
echo "=== 4. Verify Phase 1 ==="
echo "On the Pixel: open Termux, run:"
echo "  pkg update -y && pkg install -y termux-api"
echo "  termux-battery-status"
echo "If termux-battery-status prints JSON, Phase 1 is done."
