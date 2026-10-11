#!/bin/bash
# Mac-side SSH setup for Termux connection
# Run on Mac: bash setup_mac_ssh.sh

TERMUX_IP="<PIXEL_TAILSCALE_IP>"  # Pixel via Tailscale
TERMUX_PORT="8022"
KEY_NAME="termux_pixel"

echo "================================"
echo "Mac SSH Setup for Termux"
echo "================================"
echo ""

# Create SSH config directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Generate key pair if not exists
if [ ! -f "$HOME/.ssh/${KEY_NAME}" ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t ed25519 -f "$HOME/.ssh/${KEY_NAME}" -N "" -C "mac@termux"
    echo "✓ Key generated: ~/.ssh/${KEY_NAME}"
fi

# Create SSH config
cat > ~/.ssh/config << EOF
Host termux
    HostName $TERMUX_IP
    Port $TERMUX_PORT
    User termux
    IdentityFile ~/.ssh/${KEY_NAME}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

chmod 600 ~/.ssh/config

echo ""
echo "================================"
echo "Setup Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Copy public key to Termux:"
echo "   adb push ~/.ssh/${KEY_NAME}.pub /sdcard/"
echo ""
echo "2. In Termux, run:"
echo "   mkdir -p ~/.ssh"
echo "   cat /sdcard/${KEY_NAME}.pub >> ~/.ssh/authorized_keys"
echo "   chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "3. Start SSH in Termux:"
echo "   pkg install openssh -y"
echo "   sshd"
echo ""
echo "4. Connect from Mac:"
echo "   ssh termux"
echo ""
echo "Or directly:"
echo "   ssh -p $TERMUX_PORT termux@$TERMUX_IP"