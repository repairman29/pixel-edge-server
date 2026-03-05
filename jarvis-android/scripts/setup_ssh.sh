#!/data/data/com.termux/files/usr/bin/sh
# SSH Setup Script for Termux
# Run this in Termux: bash setup_ssh.sh

echo "================================"
echo "Termux SSH Setup"
echo "================================"
echo ""

# Update packages
echo "Updating packages..."
pkg update -y

# Install OpenSSH
echo "Installing OpenSSH..."
pkg install openssh -y

# Install Python for the bridge
echo "Installing Python..."
pkg install python -y

# Generate SSH keys if not exists
if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
    echo "Generating SSH keys..."
    mkdir -p $HOME/.ssh
    chmod 700 $HOME/.ssh
    ssh-keygen -t ed25519 -f $HOME/.ssh/termux_key -N "" -C "termux@pixel"
    cat $HOME/.ssh/termux_key.pub > $HOME/.ssh/authorized_keys
    chmod 600 $HOME/.ssh/authorized_keys
    echo "✓ SSH keys generated"
fi

# Start SSH daemon
echo "Starting SSH daemon..."
sshd

# Get IP address
echo ""
echo "================================"
echo "SSH Server Ready!"
echo "================================"
echo ""
IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "unknown")
echo "IP Address: $IP"
echo "Port: 8022 (default Termux SSH port)"
echo ""
echo "Connect from Mac:"
echo "  ssh -p 8022 -i ~/.ssh/termux_key termux@$IP"
echo ""
echo "Or with password (if key doesn't work):"
echo "  ssh -p 8022 termux@$IP"
echo "  Password: $(termux-keystore | head -1 || echo 'run: passwd')"
echo ""
echo "To start bridge:"
echo "  python3 ~/jarvis_bridge.py"