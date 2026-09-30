#!/usr/bin/env bash
# Android 14 phantom process killer bypass — run from host with device connected (USB debugging on).
# Raises background process limit so the agent/Termux are less likely to be killed.
# See BLUEPRINT_BEST_IN_CLASS.md §2.1. A reboot may reset; re-run if needed.

set -e
if ! command -v adb &>/dev/null; then
  echo "adb not found. Install Android platform tools."
  exit 1
fi
if ! adb devices | grep -q 'device$'; then
  echo "No device connected. Enable USB debugging and connect the Pixel."
  exit 1
fi

echo "Applying phantom process bypass..."
adb shell device_config put activity_manager max_phantom_processes 2147483647
adb shell settings put global settings_enable_monitor_phantom_procs false
adb shell device_config set_sync_disabled_for_tests persistent
echo "Done. Reboot the device if the agent still gets killed."
