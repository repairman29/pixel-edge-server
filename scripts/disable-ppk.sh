#!/usr/bin/env bash
# Disable Android Phantom Process Killer (PPK) so OpenClaw/Docker and long-lived
# daemons can run in the native Linux VM. Run from Mac with Pixel connected via USB.
# Requires USB debugging enabled and device authorized.
# See: Pixel 8 Pro Edge-Native AI Server Setup plan

set -e

echo "Checking for connected ADB device..."
if ! adb devices | grep -q "device$"; then
  echo "No device in 'device' state. Enable USB debugging, connect the Pixel, and authorize this computer."
  exit 1
fi

echo "Disabling Phantom Process Killer (PPK)..."
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
adb shell settings put global settings_enable_monitor_phantom_procs false
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"

echo "PPK disable commands completed. Reboot the device for changes to take effect."
echo "Verify with: ./scripts/verify-setup.sh"
