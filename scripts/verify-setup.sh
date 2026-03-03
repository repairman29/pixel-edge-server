#!/usr/bin/env bash
# Verify Phantom Process Killer (PPK) state on connected Pixel.
# Run from Mac with device connected via USB.
# Expected after disable-ppk.sh: max_phantom_processes=2147483647, monitor=false

set -e

echo "Checking for connected ADB device..."
if ! adb devices | grep -q "device$"; then
  echo "No device in 'device' state. Connect the Pixel and authorize this computer."
  exit 1
fi

echo "PPK-related settings:"
echo "  max_phantom_processes: $(adb shell /system/bin/device_config get activity_manager max_phantom_processes 2>/dev/null || echo 'get failed')"
echo "  settings_enable_monitor_phantom_procs: $(adb shell settings get global settings_enable_monitor_phantom_procs 2>/dev/null || echo 'get failed')"
echo ""
echo "PPK is disabled if max_phantom_processes is 2147483647 and monitor is 0 (false)."
