# What to Do to Make the Pixel Edge Server Work

End state: **Telegram → Jarvis app → OpenClaw gateway (Termux) → LLM (Jarvis HTTP :9090 or local NPU)**. The app talks to the gateway on port 18789; the gateway uses the app’s HTTP API on 9090 for the LLM.

---

## 1. Prerequisites

| What | Where |
|------|--------|
| **Pixel** (e.g. 8 Pro) with USB debugging on | Device |
| **Termux** from F-Droid | Pixel |
| **ADB** | Mac (for one-liner / pushing files) |
| **Telegram bot token** | [@BotFather](https://t.me/BotFather) → create bot → copy token |

---

## 2. On the Pixel (order matters)

### A. Termux (one-time)

1. Install **Termux** from F-Droid (not Play Store).
2. Open Termux, grant storage when asked.
3. Run: `termux-setup-storage` if you need access to `/sdcard`.

### B. Jarvis Android app

1. **Build the APK** (on Mac from this repo):
   ```bash
   cd jarvis-android
   ./gradlew assembleDebug
   ```
   APK: `app/build/outputs/apk/debug/app-debug.apk`.

2. **Install on Pixel**:
   ```bash
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

3. (Optional) **Local LLM fallback** – only if you want “!use local” to work:
   - Get a Gemma model (e.g. `gemma3-1b-it-int4.task`) and push to `/data/local/tmp/llm/model.task`.
   - Jarvis will use it when gateway is down or when user says “!use local”.

### C. OpenClaw in Termux (one-time setup)

**Option 1 – From Mac (ADB + one-liner)**  
With Pixel connected via USB:

```bash
cd pixel-edge-server
bash ONE_LINER_SETUP.sh
```

This pushes and runs the install inside Termux over ADB.

**Option 2 – Manual in Termux**  
Copy the install script onto the device (e.g. to `/sdcard/`), then in Termux:

```bash
cp /sdcard/install_openclaw_termux.sh ~   # or however you got the script there
chmod +x ~/install_openclaw_termux.sh
~/install_openclaw_termux.sh
```

Or use `setup_openclaw.sh` as in `OPENCLAW_SETUP.md`.

### D. OpenClaw config (LLM + Telegram)

OpenClaw must call **Jarvis’s HTTP API** for the LLM. In Termux:

```bash
mkdir -p ~/.config/openclaw
cat > ~/.config/openclaw/config.json << 'EOF'
{
  "llm": {
    "provider": "openai",
    "baseURL": "http://127.0.0.1:9090/v1",
    "apiKey": "local-jarvis-key",
    "model": "gemma-3b"
  },
  "telegram": {
    "botToken": "YOUR_TELEGRAM_BOT_TOKEN"
  }
}
EOF
```

Replace `YOUR_TELEGRAM_BOT_TOKEN` with the token from BotFather. Use the same token in the Jarvis app (see below).

---

## 3. Start order every time

1. **Start Jarvis first** (so port 9090 is up and gateway can call the LLM):
   - Open the Jarvis app on the Pixel.
   - Tap **START JARVIS**.
   - Wait until you see something like “HTTP API on :9090 ✓” (and optionally “Gateway connected” if the gateway is already running).

2. **Start the OpenClaw gateway** in Termux (new session if you want):
   ```bash
   cd ~/openclaw
   node bin/openclaw gateway --bind 127.0.0.1 --port 18789
   ```
   Leave this running. The Jarvis app will connect to `127.0.0.1:18789` for chat and tools.

3. **Use Telegram**  
   Message your bot (e.g. @jarvis2_pixel_bot). Try:
   - `!system`
   - `!ls /sdcard`
   - `!shell whoami`
   - Or plain chat (goes through gateway → 9090 LLM).

---

## 4. Telegram token in the app

The app needs the same bot token so it can send replies to Telegram. Either:

- **UI**: In Jarvis app, enter the token and then start the service, or  
- **Code**: It’s currently hardcoded in `JarvisService.kt` and `MainActivity.kt` as a fallback. Prefer putting the token in the UI or in a config that’s not committed.

Use one bot token for both OpenClaw config and Jarvis app.

---

## 5. Quick checks

| Check | Command / action |
|------|-------------------|
| Jarvis HTTP API up | From device: `curl -s http://127.0.0.1:9090/status` (or use “Status” in app) |
| Gateway up | In Termux: `curl -s http://127.0.0.1:18789/health` or similar (or check Jarvis “Gateway connected”) |
| Port 18789 in use | In Termux: `netstat -tlnp \| grep 18789` |
| Telegram | Send a message to your bot; you should get a reply. |

---

## 6. Troubleshooting

- **“Gateway unavailable” in Jarvis**  
  Start the OpenClaw gateway in Termux (step 3.2) and leave it running. Jarvis only connects to 127.0.0.1:18789.

- **Gateway won’t start**  
  - Ensure Jarvis is running first (9090).  
  - Ensure port 18789 is free: `netstat -tlnp | grep 18789`.

- **No reply in Telegram**  
  - Same token in `~/.config/openclaw/config.json` and in the Jarvis app.  
  - Bot is started by the app; gateway only does the chat/tool loop. Don’t start a second Telegram client in OpenClaw if the app is already running the bot.

- **Cleartext / connection errors on Android**  
  The app already has `networkSecurityConfig` and `usesCleartextTraffic` for 127.0.0.1. If you use another host/port, you may need to adjust `res/xml/network_security_config.xml`.

---

## Summary

1. Install Termux (F-Droid) and Jarvis APK; optionally push LLM model.  
2. Run OpenClaw install in Termux (one-liner from Mac or manual script).  
3. Set `~/.config/openclaw/config.json` with `baseURL: http://127.0.0.1:9090/v1` and your Telegram bot token.  
4. Each time: start **Jarvis app** first, then **OpenClaw gateway** in Termux; use Telegram to talk to the bot.

After that, the Pixel edge server is running: Telegram → Jarvis (app) ↔ OpenClaw (gateway) → Jarvis HTTP (:9090) / NPU.
