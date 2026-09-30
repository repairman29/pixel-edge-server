#!/data/data/com.termux/files/usr/bin/sh
# Start ollama-proxy and gateway - designed to run from Termux
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=$HOME/tmp
export TMP=$TMPDIR
export PORT=18789

cd $HOME/JARVIS

# Start ollama-proxy (forwards 11434 -> 8889 for Ragionare)
nohup node scripts/ollama-proxy.js >> $HOME/tmp/proxy.log 2>&1 &
echo "ollama-proxy PID: $!"

# Small delay
sleep 2

# Start gateway
nohup node scripts/start-gateway-background.js >> $HOME/gateway.log 2>&1 &
echo "gateway PID: $!"

# Wait a bit and check
sleep 10
curl -s http://127.0.0.1:18789/ > /dev/null && echo "Gateway is UP" || echo "Gateway is DOWN"
curl -s http://127.0.0.1:11434/api/tags > /dev/null && echo "Proxy is UP" || echo "Proxy is DOWN"
