#!/data/data/com.termux/files/usr/bin/bash
# Jarvy Setup Script for OpenClaw

mkdir -p ~/.config/openclaw
mv /sdcard/openclaw-config.json ~/.config/openclaw/config.json
chmod 600 ~/.config/openclaw/config.json

cd ~/openclaw
nohup node dist/entry.js gateway --bind loopback --port 18791 > /data/local/tmp/openclaw.log 2>&1 &

echo "Jarvy (OpenClaw) started on port 18791!"
echo "Check logs: tail -f /data/local/tmp/openclaw.log"
