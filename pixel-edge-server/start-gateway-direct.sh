#!/data/data/com.termux/files/usr/bin/bash
export TMPDIR=/data/data/com.termux/files/home/tmp
mkdir -p /data/data/com.termux/files/home/tmp
cd /data/data/com.termux/files/home/JARVIS
/data/data/com.termux/files/home/JARVIS/node_modules/.bin/clawdbot gateway run --allow-unconfigured --port 18790 --bind lan > /data/data/com.termux/files/home/gateway-new.log 2>&1
