# SSH Setup for Termux

## Quick Setup (5 minutes)

### Step 1: Setup SSH in Termux (on Pixel)

Open Termux and run:
```bash
curl -o ~/setup_ssh.sh https://raw.githubusercontent.com/repairman29/jarvis-android/main/scripts/setup_ssh.sh
bash ~/setup_ssh.sh
```

Or manually:
```bash
# Install OpenSSH
pkg install openssh -y

# Start SSH server
sshd

# Optional: Set password
passwd
```

### Step 2: Connect from Mac

**Option A: Using Tailscale IP (recommended)**
```bash
ssh -p 8022 termux@100.78.73.64
```

**Option B: Using ADB port forward**
```bash
# Forward port 8022 from Pixel to Mac
adb forward tcp:8022 tcp:8022

# Then connect
ssh -p 8022 termux@localhost
```

## Setting Up Key-Based Auth (More Secure)

### On Mac:
```bash
# Generate key
ssh-keygen -t ed25519 -f ~/.ssh/termux_pixel

# Copy public key to device
adb push ~/.ssh/termux_pixel.pub /sdcard/
```

### In Termux:
```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat /sdcard/termux_pixel.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Back on Mac:
```bash
# Create SSH config
cat >> ~/.ssh/config << 'EOF'
Host termux-pixel
    HostName 100.78.73.64
    Port 8022
    User termux
    IdentityFile ~/.ssh/termux_pixel
    StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/config

# Now just run: ssh termux-pixel
ssh termux-pixel
```

## Running the Bridge via SSH

Once connected via SSH:
```bash
# Install Python if not done
pkg install python -y

# Copy bridge script
cp /sdcard/jarvis/scripts/termux_bridge.py ~/jarvis_bridge.py

# Run bridge
python3 ~/jarvis_bridge.py
```

Leave this running in the SSH session.

## Making SSH Persistent

### Auto-start SSH on Termux boot:
```bash
# Install termux-boot
pkg install termux-boot

# Create startup script
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-sshd << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
sshd
EOF

chmod +x ~/.termux/boot/start-sshd
```

### Run Bridge via SSH without keeping terminal open:
```bash
# Install screen or tmux
pkg install tmux -y

# Start bridge in tmux
tmux new-session -d -s jarvis 'python3 ~/jarvis_bridge.py'

# Detach: Ctrl+B then D

# Reattach later:
tmux attach -t jarvis
```

## Using SSH for Direct Commands

You can also execute commands directly without the bridge:

```bash
# Check storage
ssh -p 8022 termux@100.78.73.64 'df -h'

# List files
ssh -p 8022 termux@100.78.73.64 'ls -la /sdcard'

# Run Python
ssh -p 8022 termux@100.78.73.64 'python3 -c "print(2+2)"'

# Install packages
ssh -p 8022 termux@100.78.73.64 'pkg install nodejs -y'
```

## Troubleshooting

### "Connection refused"
- SSH daemon not running: `sshd`
- Wrong port: default is 8022, not 22
- Firewall: check `iptables -L`

### "Permission denied"
- Wrong password
- Key not authorized: check `~/.ssh/authorized_keys`
- Wrong permissions: `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys`

### "No route to host"
- Pixel not on same network
- Tailscale not connected: check `tailscale status`
- Wrong IP: verify with `ip addr` in Termux

### Can't find IP
In Termux:
```bash
# Get IP
ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1

# Or install net-tools
pkg install net-tools
ifconfig wlan0
```

## Advanced: SSH Tunnel for HTTP

Forward Jarvis HTTP port through SSH:
```bash
# On Mac, forward port 9090 from Pixel to localhost:9090
ssh -p 8022 -L 9090:localhost:9090 termux@100.78.73.64

# Now access on Mac:
curl http://localhost:9090/status
```

## Security Notes

- Default SSH port in Termux is **8022** (not 22)
- Password auth is enabled by default
- For production, disable password auth and use keys only
- Termux runs as non-root user (safer)
- All files in `/sdcard` are accessible by both Termux and Android apps