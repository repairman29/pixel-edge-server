# OpenClaw on Termux (Pixel) — no install.sh

The official install script (`curl -fsSL https://openclaw.ai/install.sh | bash`) only supports macOS and standard Linux (`OSTYPE=linux-gnu*` or WSL). **Termux reports `linux-android` or empty `OSTYPE`, so the script exits with "Unsupported operating system".**

Use this **npm-only** path instead. Requires **Node.js 22+** in Termux.

---

## 1. In Termux: install Node 22+ if needed

```bash
# Check version (need 22.x or higher)
node --version

# If too old, install/upgrade (Termux may ship Node 20; check pkg or use nvm/fnm)
pkg update && pkg install nodejs -y
# If still < 22, you may need NodeSource or build from source; see Termux wiki.
```

---

## 2. Install OpenClaw globally via npm (no install script)

```bash
npm install -g openclaw@latest
```

This skips the official installer and only installs the OpenClaw CLI. No daemon (launchd/systemd) is installed — Termux doesn't have those; you'll start the gateway manually or via a script.

---

## 3. Create config and run the gateway

```bash
# One-time: create workspace/config (or copy from your Mac)
mkdir -p ~/.config/openclaw
# Edit ~/.config/openclaw/config.json or use `openclaw onboard` (wizard may have limits on Termux)

# Run gateway so Jarvis app (and later other bots) can reach it
# Bind 0.0.0.0 so the device is reachable on the network (Tailscale/LAN)
openclaw gateway --port 18789 --bind 0.0.0.0
```

- **Port 18789**: Jarvis Android app expects the gateway here.
- **--bind 0.0.0.0**: Listens on all interfaces so other bots can hit the Pixel at its LAN or Tailscale IP later.

---

## 4. Optional: fake OSTYPE to run the install script (not recommended)

If you really want to run the official script (e.g. to get the wizard), you can try:

```bash
OSTYPE=linux-gnu bash -c 'curl -fsSL https://openclaw.ai/install.sh | bash'
```

The script may still fail later (e.g. apt, systemd, or other Linux-specific steps). Prefer the npm path above.

---

## Summary

| Step | Command / note |
|------|-----------------|
| Node 22+ | `pkg install nodejs` (or upgrade as needed) |
| Install OpenClaw | `npm install -g openclaw@latest` |
| Run gateway | `openclaw gateway --port 18789 --bind 0.0.0.0` |

No `install.sh` required.

---

## Troubleshooting (from device logs)

### 1. `npm install -g openclaw` fails on **koffi** (native build)

OpenClaw depends on **koffi** (native Node addon). On Termux the build can fail with:

- `make: the '-j' option requires a positive integer argument`
- `Failed to load prebuilt binary, rebuilding from source` then the make step fails.

**Cause:** The koffi build runs `make -j` without a number; Termux’s make (or the jobserver) doesn’t accept that.

**Workarounds:**

- **Option A – Give make a job count (in Termux before `npm install`):**
  ```bash
  export npm_config_make_jobs=1
  npm install -g openclaw@latest
  ```
  If the build script doesn’t respect that, try:
  ```bash
  export MAKE_JOBS=1
  npm install -g openclaw@latest
  ```

- **Option B – Skip optional native builds (may work if OpenClaw doesn’t require koffi for your use):**
  ```bash
  npm install -g openclaw@latest --ignore-scripts
  ```
  Then run `openclaw gateway` and see if it starts. If it fails on missing koffi, you’ll need Option A or a Debian proot.

- **Option C – Install OpenClaw inside a Debian proot** in Termux (`pkg install proot-distro`, then `proot-distro install debian`), where `make -j` and prebuilds often work.

### 2. **TelegramBot: Polling error: getUpdates failed: 409** (logcat)

HTTP **409** from Telegram means **another client is already long‑polling** the same bot token. Only one process can call `getUpdates` per bot.

**Fix:** Use the token in only one place:

- If **OpenClaw** in Termux will handle Telegram: disable or don’t start the Telegram bot in the **Jarvis Android app** (or use a different bot token for the app).
- If the **Jarvis app** should handle Telegram: disable Telegram in OpenClaw config (e.g. in `~/.clawdbot/clawdbot.json` or OpenClaw’s config) or don’t enable the Telegram channel there.
