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
