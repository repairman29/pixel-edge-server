# Termux SSH setup (run build/gateway from Mac)

## On the Pixel (Termux)

1. **Start sshd** (if not already running):
   ```bash
   sshd
   ```
   It listens on port 8022.

2. **Set a password** so the Mac can log in:
   ```bash
   passwd
   ```

3. **Get your username** (you’ll need it on the Mac):
   ```bash
   whoami
   ```
   Example: `u0_a123`. Set that as `TERMUX_SSH_USER` on the Mac.

## On the Mac

1. **Install sshpass** (so the script can send the password non-interactively):
   ```bash
   brew install sshpass
   ```

2. **Set username and password** (one of these):
   - Env (each terminal session):
     ```bash
     export TERMUX_SSH_USER=u0_a123   # use output of whoami from Termux
     export TERMUX_SSH_PASS=yourpass
     ```
   - Or put the password in a file (gitignored):
     ```bash
     echo -n yourpass > pixel-edge-server/scripts/.termux-ssh-pass
     export TERMUX_SSH_USER=u0_a123
     ```

3. **Connect the Pixel** with USB and ensure `adb devices` shows the device.

4. **Run build** (5–15 min):
   ```bash
   cd pixel-edge-server
   ./scripts/run-build-via-ssh.sh
   ```

5. **Start the gateway** (after build):
   ```bash
   ./scripts/start-gateway-via-ssh.sh
   ```

6. **Test**:
   ```bash
   ./scripts/start-gateway-and-test.sh
   ```
