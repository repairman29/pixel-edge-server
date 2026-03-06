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

## 7. Health monitoring & self-heal (3 layers)

Three layers of resilience keep the stack running autonomously:

**Layer 1: Watchdog** (every 2 min, no AI) — checks all ports (3456, 18789, 8080, 11434, 8096) and Docker containers. Restarts anything dead, verifies recovery.

```bash
bash scripts/setup-watchdog.sh            # install from Mac
# Log:
ssh -p 8022 droid@100.78.73.64 'tail ~/watchdog/watchdog.log'
```

**Layer 2: OpenClaw orchestrator** (every 10 min, AI-driven) — OpenClaw dispatches a full management task to Claude Gateway `/v1/agent`. Claude checks services, restarts failures, monitors thermal/disk/memory, rotates logs, and writes a structured status file.

```bash
bash scripts/setup-openclaw-orchestrator.sh   # install from Mac
# Status:
ssh -p 8022 droid@100.78.73.64 'cat ~/openclaw-orchestrator/status.md'
```

**Layer 3: Claude heartbeat** (every 30 min, AI diagnostic) — deeper analysis with remediation authority. Install with `./scripts/setup-claude-heartbeat.sh`. See **[docs/claude-gateway.md](claude-gateway.md)** → AI Heartbeat section.

All systemd services also have `Restart=on-failure` (Claude Gateway) or `Restart=always` (OpenClaw) as a baseline.

---

## 8. Port reference

All services and their ports. Internal scripts use `127.0.0.1`; reach the device from your Mac via Tailscale (`100.78.73.64`) or LAN IP.

| Service | Port | Internal URL | Tailscale URL | Notes |
|---------|------|-------------|--------------|-------|
| Claude Gateway | 3456 | `http://127.0.0.1:3456` | `http://100.78.73.64:3456` | `/health`, `/metrics`, `/v1/chat/completions`, `/v1/agent` |
| OpenClaw gateway | 18789 | `http://127.0.0.1:18789` | `http://100.78.73.64:18789` | Mission Control UI + API |
| llama-server (llama.cpp) | 8080 | `http://127.0.0.1:8080` | `http://100.78.73.64:8080` | Optional; installed by `setup-llama-sve.sh` |
| Ollama (Docker) | 11434 | `http://127.0.0.1:11434` | `http://100.78.73.64:11434` | Optional; installed by `setup-homelab.sh` |
| Jellyfin (Docker) | 8096 | `http://127.0.0.1:8096` | `http://100.78.73.64:8096` | Optional; installed by `setup-homelab.sh` |
| VM SSH | 8022 | — | `ssh -p 8022 droid@100.78.73.64` | Or `droid@127.0.0.1` over USB |

**Environment variables** that configure these:

| Variable | Where used | Default |
|----------|-----------|---------|
| `ANTHROPIC_API_KEY` | `claude-gateway/.env` on VM | *(required — no default)* |
| `CLAUDE_GATEWAY_PORT` | `claude-gateway/.env` on VM | `3456` |
| `CLAUDE_MODEL` | `claude-gateway/.env` on VM | `claude-opus-4-6` |
| `CLAUDE_GATEWAY_URL` | `openclaw-orchestrator.sh`, `claude-heartbeat.sh` on VM | `http://127.0.0.1:3456` |
| `LOCAL_LLM_URL` | `claude-gateway/.env` on VM | *(unset — local LLM disabled)* |
| `GATEWAY_API_KEY` | `claude-gateway/.env` on VM | *(unset — no auth required)* |
