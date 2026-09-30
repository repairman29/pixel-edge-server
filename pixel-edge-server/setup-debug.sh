#!/bin/bash
# Debug setup - writes output to file

exec > /sdcard/setup-debug.log 2>&1

echo "Starting setup..."

# Copy authorized_keys
mkdir -p ~/.ssh
cp /sdcard/authorized_keys ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
ls -la ~/.ssh

# Copy config
mkdir -p ~/.config/openclaw
cp /sdcard/CHROOT_MASTER_CONFIG.json ~/.config/openclaw/config.json
ls -la ~/.config/openclaw/config.json

# Restart sshd
pkill sshd 2>/dev/null
sleep 1
/usr/bin/sshd

echo "Done!"
ps aux | grep ssh
