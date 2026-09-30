#!/data/data/com.termux/files/usr/bin/bash
H=/data/data/com.termux/files/home
P=/data/data/com.termux/files/usr
export HOME=$H
export PATH=$P/bin:$PATH
export TMPDIR=$H/tmp
export TMP=$H/tmp
export PORT=18789
export BIND_LAN=1

mkdir -p $H/tmp

pkill -f 'clawdbot gateway' 2>/dev/null || true
pkill -f 'gateway run' 2>/dev/null || true
sleep 1

cd $H/JARVIS
echo "[$(date)] starting gateway native" >> $H/gateway.log
nohup $P/bin/node scripts/start-gateway-background.js >> $H/gateway.log 2>&1 &
GW_PID=$!
echo "[$(date)] gateway spawner PID=$GW_PID" >> $H/gateway.log

sleep 8
echo "[$(date)] checking gateway..." >> $H/gateway.log
ps -A | grep -E 'clawdbot|npx' | grep -v grep >> $H/gateway.log 2>/dev/null || true
curl -s -o /dev/null -w "gateway http_code=%{http_code}\n" http://127.0.0.1:18789/ >> $H/gateway.log 2>&1 || true
