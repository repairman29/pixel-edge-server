#!/bin/bash
exec > /sdcard/chroot-start.log 2>&1
echo "Starting chroot master at $(date)..."

# Run the startup script
bash /sdcard/start-chroot-master.sh

echo "Script finished at $(date)"
