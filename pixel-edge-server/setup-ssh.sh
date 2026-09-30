#!/bin/bash
# Setup SSH access for opencode

# Copy authorized_keys
mkdir -p ~/.ssh
cp /sdcard/authorized_keys ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Copy config
cp /sdcard/CHROOT_MASTER_CONFIG.json ~/.config/openclaw/config.json

# Restart sshd
pkill sshd
sshd

echo "SSH setup complete!"
