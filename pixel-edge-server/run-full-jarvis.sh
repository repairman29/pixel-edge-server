#!/data/data/com.termux/files/usr/bin/bash
# FINAL SOLUTION: Run JARVIS stack which handles /tmp properly

echo "=========================================="
echo "  JARVIS Full Stack Startup"
echo "=========================================="
echo ""

# The JARVIS startup script should handle the /tmp issue
# It sets up proper environment before starting services

cd ~/JARVIS

# Kill any existing processes
pkill -9 -f "clawdbot gateway" 2>/dev/null
pkill -9 -f ":18789" 2>/dev/null
sleep 2

echo "Starting full JARVIS stack..."
echo "This will start:"
echo "  - InferrLM proxy (8888)"
echo "  - Gateway (18789)"
echo "  - Chat server (18888)"
echo "  - Other services"
echo ""

# Run the official startup script
bash scripts/start-jarvis-pixel.sh 2>&1 | tee ~/jarvis-start.log

echo ""
echo "=========================================="
echo "Check status with:"
echo "  tail -f ~/jarvis-start.log"
echo ""
echo "Test gateway:"
echo "  curl http://127.0.0.1:18789/health"
echo "=========================================="
