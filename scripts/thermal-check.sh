#!/bin/bash
# Run inside the Pixel Debian VM. Checks thermal sensors if available and logs/warns.
# Optional: add to cron (e.g. every 5 min) or run manually.
# Threshold in millidegrees C (45000 = 45C). Some hosts expose thermal via /sys.

THRESHOLD_MC=${THRESHOLD_MC:-40000}
LOG=${LOG:-/tmp/thermal-check.log}

for zone in /sys/class/thermal/thermal_zone*/temp 2>/dev/null; do
  [ -f "$zone" ] || continue
  read -r mc < "$zone" 2>/dev/null || continue
  name=$(cat "${zone%/*}/type" 2>/dev/null) || name="unknown"
  if [ -n "$mc" ] && [ "$mc" -gt "$THRESHOLD_MC" ]; then
    msg="$(date -Iseconds) thermal $name=${mc}mC (above ${THRESHOLD_MC}mC)"
    echo "$msg" >> "$LOG"
    echo "$msg" >&2
  fi
done

# If no thermal zones found, nothing to do (common in VMs)
exit 0
