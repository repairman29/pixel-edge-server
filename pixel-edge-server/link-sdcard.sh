#!/bin/bash
# Link sdcard files to termux home

# Link JARVIS
ln -sf /sdcard/jarvis ~/JARVIS

# Link config
mkdir -p ~/.config/openclaw
cp /sdcard/CHROOT_MASTER_CONFIG.json ~/.config/openclaw/config.json

# Create tmp
mkdir -p ~/tmp

# Link auth
cp /sdcard/authorized_keys ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "Setup complete!"
ls -la ~/
