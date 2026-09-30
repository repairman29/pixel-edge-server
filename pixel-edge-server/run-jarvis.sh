#!/data/data/com.termux/files/usr/bash
# Fixed paths - use sdcard jarvis directly

WORKSPACE="/sdcard/jarvis"
LOG_FILE="/sdcard/chroot.log"
PORT=18790

echo "Starting from $WORKSPACE"

cd $WORKSPACE
./node_modules/.bin/clawdbot gateway run --port $PORT --bind lan 2>&1 | tee $LOG_FILE
