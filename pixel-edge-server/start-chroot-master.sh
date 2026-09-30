#!/data/data/com.termux/files/usr/bin/bash
# START CHROOT MASTER - Unified OpenClaw with Maximum Capabilities
# Port: 18790 (avoids Maclawd conflict on 18789/18791/18792)

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        CHROOT MASTER - Maximum Capabilities Mode               ║"
echo "║        Port: 18790  |  Discord + MiniCPM4                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
CHROOT_PORT=18790
CHROOT_CONFIG="/data/data/com.termux/files/home/.config/openclaw/config.json"
WORKSPACE="/data/data/com.termux/files/home/JARVIS"
LOG_FILE="/data/data/com.termux/files/home/tmp/chroot-master.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Step 1: Kill existing instances
print_status "Step 1/7: Cleaning up existing instances..."
pkill -9 -f "clawdbot" 2>/dev/null || true
pkill -9 -f "clawdbot-gateway" 2>/dev/null || true
sleep 2
print_success "Existing instances killed"

# Step 2: Verify environment
print_status "Step 2/7: Verifying chroot environment..."
if [ ! -d "$HOME/JARVIS" ]; then
    print_error "JARVIS directory not found at $HOME/JARVIS"
    exit 1
fi

if [ ! -d "$HOME/.config/openclaw" ]; then
    print_error "OpenClaw config directory not found"
    exit 1
fi

print_success "Environment verified"

# Step 3: Create required directories
print_status "Step 3/7: Creating required directories..."
mkdir -p "$HOME/tmp"
mkdir -p "$HOME/.clawdbot/agents/main/agent"
mkdir -p "$WORKSPACE"
print_success "Directories created"

# Step 4: Check for auth-profiles.json
print_status "Step 4/7: Setting up authentication..."
AUTH_FILE="$HOME/.clawdbot/agents/main/agent/auth-profiles.json"
if [ ! -f "$AUTH_FILE" ]; then
    print_warning "Creating auth-profiles.json for farm provider..."
    cat > "$AUTH_FILE" << 'EOF'
{
  "farm": {
    "apiKey": "sk-local-farm"
  }
}
EOF
    print_success "Auth profiles created"
else
    print_success "Auth profiles already exist"
fi

# Step 5: Verify MiniCPM4 availability
print_status "Step 5/7: Checking MiniCPM4 availability..."
if curl -s http://127.0.0.1:8889/v1/models 2>/dev/null | grep -q "minicpm4"; then
    print_success "MiniCPM4 is available on port 8889"
else
    print_warning "MiniCPM4 not responding on port 8889"
    print_warning "You may need to start: llama-server -m /path/to/minicpm4.gguf --port 8889"
fi

# Step 6: Apply chroot configuration
print_status "Step 6/7: Applying CHROOT_MASTER configuration..."

# Copy config from sdcard (pushed earlier)
if [ -f "/sdcard/CHROOT_MASTER_CONFIG.json" ]; then
    cp "/sdcard/CHROOT_MASTER_CONFIG.json" "$CHROOT_CONFIG"
    print_success "Configuration applied"
else
    print_warning "CHROOT_MASTER_CONFIG.json not on sdcard, using existing config"
fi

# Verify port setting
if ! grep -q "\"port\": $CHROOT_PORT" "$CHROOT_CONFIG"; then
    print_error "Port $CHROOT_PORT not configured in config!"
    exit 1
fi

# Step 7: Start the gateway
print_status "Step 7/7: Starting CHROOT_MASTER gateway..."
echo ""

cd "$HOME/JARVIS"

# Start with proper environment
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/home/tmp

# Use termux-chroot for full Linux environment
termux-chroot bash -c "
    export HOME=/home
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH
    mkdir -p /tmp/clawdbot
    cd $HOME/JARVIS
    
    echo 'Starting clawdbot gateway...'
    ./node_modules/.bin/clawdbot gateway run \
        --port $CHROOT_PORT \
        --bind lan \
        2>&1 | tee /home/tmp/chroot-master.log
" &

CHROOT_PID=$!

print_success "Gateway started (Background PID: $CHROOT_PID)"
echo ""

# Wait and verify
sleep 3
print_status "Verifying gateway startup..."

if ps | grep -q "clawdbot-gateway"; then
    print_success "CHROOT_MASTER is running!"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Discord bot should appear online within 30 seconds"
    echo ""
    echo "  Check status:"
    echo "    tail -f ~/tmp/chroot-master.log"
    echo ""
    echo "  Monitor processes:"
    echo "    ps | grep claw"
    echo ""
    echo "  Stop gateway:"
    echo "    pkill -9 -f clawdbot"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Show recent logs
    sleep 2
    if [ -f "$LOG_FILE" ]; then
        echo "Recent log entries:"
        echo "───────────────────────────────────────────────────────────────"
        tail -15 "$LOG_FILE" 2>/dev/null || echo "(Log file not yet created)"
        echo "───────────────────────────────────────────────────────────────"
    fi
else
    print_error "Gateway failed to start!"
    echo "Check logs: tail -f ~/tmp/chroot-master.log"
    exit 1
fi

echo ""
echo "✨ CHROOT_MASTER is now ONLINE and ready for maximum capabilities!"
echo ""
