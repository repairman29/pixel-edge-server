# Pixel 8 Pro Edge Server – Optional Setup

## 1. SSH over Wi‑Fi (LAN)

The Terminal app has an **SSH** toggle for port 8022. On some builds it does not expose the VM’s SSH to the LAN; if it does, from your Mac (same Wi‑Fi as the Pixel):

```bash
ssh -p 8022 droid@10.1.10.29
```

Replace with the Pixel’s current LAN IP (Settings → Network). If you get “Connection refused”, use **Tailscale** or **USB (adb forward)** instead; see the main [pixel-edge-server-setup.md](pixel-edge-server-setup.md).

---

## 2. Wakelock (avoid deep sleep)

To reduce the chance of the VM pausing when the screen is off:

- **Keep the Terminal app in the foreground** when you want the server running 24/7, or leave the screen on (e.g. plugged in, developer option to stay awake).
- The native Android Terminal app does not expose a wakelock API like Termux’s `termux-wake-lock`. For always-on, use **Settings → Developer options → Stay awake** when charging, or keep the device awake by your own means.

---

## 3. Tensor G3 taskset (core pinning)

Pin heavy work to the right cores for lower latency and better stability.

**Core layout (Tensor G3):** 1× Prime (Cortex-X3), 4× Middle (Cortex-A715), 4× Little (Cortex-A510).

**In the VM, see which CPU is which:**

```bash
lscpu
cat /proc/cpuinfo | grep -E 'processor|model name'
```

Typical mapping: core 0 = prime; 1–4 = middle; 5–8 = little (verify on your device).

**Examples:**

- Run OpenClaw gateway on the prime core only:
  ```bash
  taskset -c 0 openclaw gateway
  ```
- Run a one-off LLM/script on prime:
  ```bash
  taskset -c 0 ./your-llm-script
  ```
- Background / Tailscale on little cores (e.g. 5–8):
  ```bash
  taskset -c 5-8 tailscale ...
  ```

The **setup-openclaw-daemon.sh** script can install a systemd service that runs the gateway with `taskset -c 0`.

---

## 4. Thermal check (optional script)

A small script in the VM can read thermal sensors (if exposed) and log or throttle. Install and run it from the VM; see **scripts/setup-thermal-check.sh** (run from Mac) to deploy it.

Best practice regardless: use the device **without a thick case** and on a **cool surface** for long runs.

---

## 5. OpenClaw as a persistent daemon

So the gateway survives disconnects and VM restarts, install it as a **systemd user service**. From your Mac:

```bash
./scripts/setup-openclaw-daemon.sh
```

(Optionally pass the VM target, e.g. `droid@100.78.73.64`.) This creates the service and enables it; the gateway will start on boot and restart on failure.

---

## 6. OpenClaw agent tools (shell & file access)

The agent is configured with **full** tool access so it can run shell commands, read/write/edit files (e.g. `SOUL.md`), use cron, and other “Jarvis-style” control from Telegram/Discord. In `~/.openclaw/openclaw.json`: `"tools": { "profile": "full" }` and `"tools.exec": { "host": "gateway", "security": "full", "ask": "off" }` so shell commands run on the VM with no allowlist or approval prompts.

**To restrict again** (messaging-only, no shell/file):

- SSH into the VM and edit `~/.openclaw/openclaw.json`: set `"tools": { "profile": "messaging" }`, then restart: `systemctl --user restart openclaw-gateway`.

The agent runs with the same privileges as the `droid` user in the VM; keep your allowlist (e.g. `allowFrom`) tight so only you can send it commands.

---

## 7. Gateway health-check (self-heal)

A script runs **every 5 minutes** (systemd user timer): if nothing is listening on port 18789, it restarts the OpenClaw gateway. So if the process dies without systemd noticing, the next run brings it back.

**Install (from Mac):**
```bash
./scripts/setup-gateway-healthcheck.sh
```

**Log:** `ssh -p 8022 droid@100.78.73.64 'tail ~/openclaw-heartbeat/gateway-healthcheck.log'`

---

## 8. Gateway crashing

If the gateway keeps crashing (Telegram/Discord stop responding, or you see restarts in the VM):

1. **Capture logs** (from Mac, after SSH works):
   ```bash
   adb forward tcp:8022 tcp:8022   # if using USB
   ./scripts/capture-gateway-crash-log.sh droid@127.0.0.1
   ```
   Opens `gateway-crash-log.txt` with the last 200 lines of gateway journal + dmesg tail.

2. **Re-apply the daemon** with a memory limit and longer restart delay (reduces OOM and crash-loop thrashing):
   ```bash
   ./scripts/setup-openclaw-daemon.sh
   ```
   (Use `droid@127.0.0.1` after `adb forward` for USB.)

3. **Common causes:** low VM RAM (gateway now capped at 450M), Telegram 409 (only one bot instance), or an uncaught error in OpenClaw—check the captured log for the last stack trace or “Out of memory”.

---

## 9. iPhone Shortcut: “Wake Jarvis” (restart gateway from Tailscale)

A small HTTP server runs on the Pixel VM (port 9180) so any device on your Tailscale network—including an iPhone—can restart the OpenClaw gateway with one tap.

**Install (from Mac, once):**
```bash
./scripts/setup-jarvis-wake.sh
```
Use `droid@127.0.0.1` after `adb forward tcp:8022 tcp:8022` for USB. The script prints a **token** and the URL; save them.

**iPhone Shortcut:**
1. Open **Shortcuts** → **New Shortcut** → **Add Action**.
2. Search for **“Get Contents of URL”** and add it.
3. Set **URL** to: `http://100.78.73.64:9180/restart-gateway?token=YOUR_TOKEN`  
   (Replace with your Pixel Tailscale IP and the token from the setup script.)
4. Optionally add **“Show Result”** or **“Show Notification”** so you see “OK gateway restarting”.
5. Name the shortcut (e.g. “Wake Jarvis”) and add it to the home screen or ask Siri to run it.

When the bot isn’t responding, run the shortcut; wait ~30 seconds, then try the bot again.
