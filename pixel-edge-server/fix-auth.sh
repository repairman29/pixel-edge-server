#!/data/data/com.termux/files/usr/bin/bash
# Fix auth for miniCPM4

echo "Creating auth file..."

# Create directory
mkdir -p ~/.clawdbot/agents/main/agent

# Create auth file
cat > ~/.clawdbot/agents/main/agent/auth-profiles.json << 'EOF'
{
  "farm": {
    "apiKey": "sk-local-farm"
  }
}
EOF

echo "Auth file created:"
cat ~/.clawdbot/agents/main/agent/auth-profiles.json

echo ""
echo "Now run: termux-chroot bash -c 'cat > /home/.clawdbot/agents/main/agent/auth-profiles.json << EOF
{
  \"farm\": {
    \"apiKey\": \"sk-local-farm\"
  }
}
EOF'"
