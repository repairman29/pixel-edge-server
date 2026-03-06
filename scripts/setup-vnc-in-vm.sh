#!/usr/bin/env bash
# Install a minimal VNC server and X session in the Pixel Debian VM so you can run a Linux desktop.
# Run from your Mac. Usage: ./scripts/setup-vnc-in-vm.sh [droid@100.78.73.64]
# After setup, run in the VM: vncserver :1 . Then connect to 100.78.73.64:5901 with a VNC client.
# Pixel 8 Pro uses software rendering (lavapipe); GUI works but is not GPU-accelerated.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/vm-common.sh"

vm_banner "VNC + minimal desktop"

vm_ssh_heredoc << 'REMOTE'
set -e
sudo apt update
sudo apt install -y tigervnc-standalone-server xfce4 xfce4-goodies dbus-x11
# Optional: set VNC password. Default: run vncpasswd in the VM after first login.
mkdir -p ~/.vnc
REMOTE

echo ""
echo "VNC and Xfce are installed. Next steps (in the VM):"
echo "  1. Set a VNC password: vncpasswd"
echo "  2. Start the server:  vncserver :1"
echo "  3. From your Mac or phone VNC client, connect to 100.78.73.64:5901"
echo ""
echo "To start VNC now over SSH:"
echo "  ssh -p ${VM_PORT} ${VM_HOST} 'vncserver :1 -geometry 1280x720 -depth 24'"
echo "Stop with: ssh -p ${VM_PORT} ${VM_HOST} 'vncserver -kill :1'"
