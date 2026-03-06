# Pixel 8 Pro Edge Server – Quick Reference

Fill in the placeholders after setup. Use this for SSH, Docker, and OpenClaw from your Mac.

## Connection details

| Item | Value |
|------|--------|
| SSH port (VM) | `8022` |
| Pixel LAN IP | `10.1.10.29` |
| Tailnet IP (VM) | `100.78.73.64` |
| Linux username (VM) | `droid` |
| Mission Control (OpenClaw) | port `18789` |

## One-line commands

**SSH via USB (ADB) – use when Wi‑Fi forwarding doesn’t work:**
```bash
adb forward tcp:8022 tcp:8022
ssh -p 8022 droid@127.0.0.1
```
Run the `adb forward` line after each USB reconnect or device reboot.

**SSH via LAN (same network as Pixel):**
```bash
ssh -p 8022 droid@10.1.10.29
```

**SSH via Tailscale (from anywhere):**
```bash
ssh -p 8022 droid@100.78.73.64
```

**Mission Control in browser:**
```text
http://100.78.73.64:18789
```
Or use the Pixel LAN IP if you’re on the same network and port 18789 is forwarded.

**Docker (run inside VM after SSH):**
```bash
docker run hello-world
docker ps
```

**OpenClaw (run inside VM; start gateway):**
```bash
# From OpenClaw repo directory, e.g.:
npm start
# Or with pm2 for persistence:
pm2 start npm --name openclaw -- start
```

## Port forwarding (Terminal app)

In **Terminal app → Settings**, turn **SSH** toggle **ON** for port `8022`. Optionally add port `18789` for Mission Control when running OpenClaw.

## Verify PPK state (from Mac)

```bash
./scripts/verify-setup.sh
```

## Fix VM and run review (from Mac)

One script to set up SSH key (once), install OpenClaw if needed, start the gateway, and run the review. **Run in Terminal on your Mac** (so you can enter the VM password when asked):

```bash
cd /Users/jeffadkins/Projects
./scripts/fix-vm-and-review.sh
```

Uses Tailscale by default (`droid@100.78.73.64`). For USB: `adb forward tcp:8022 tcp:8022` then `./scripts/fix-vm-and-review.sh droid@127.0.0.1`.

## Optional setup

See **[docs/optional-setup.md](optional-setup.md)** for:

- **SSH over Wi‑Fi** – When the Terminal app exposes port 8022 to the LAN.
- **Wakelock** – Keeping the device from deep sleep during long runs.
- **Tensor G3 taskset** – Pinning OpenClaw/LLM to the prime core.
- **Thermal check** – Script in the VM that logs high temps (if sensors are exposed).
- **OpenClaw as a daemon** – Persist across reboots:

```bash
./scripts/setup-openclaw-daemon.sh
```

**Thermal check** (deploy script to VM and cron):

```bash
./scripts/setup-thermal-check.sh
```

## Claude Gateway (AI server)

Your Pixel now runs a **Claude Opus 4.6 inference server** — OpenAI-compatible + agentic:

| Item | Value |
|------|-------|
| Gateway port | `3456` |
| Chat endpoint | `POST http://100.78.73.64:3456/v1/chat/completions` |
| Agent endpoint | `POST http://100.78.73.64:3456/v1/agent` |
| Streaming agent | `POST http://100.78.73.64:3456/v1/agent/stream` |
| Metrics | `GET  http://100.78.73.64:3456/metrics` |
| Health check | `GET  http://100.78.73.64:3456/health` |

**Deploy:**
```bash
export ANTHROPIC_API_KEY=sk-ant-...
./scripts/setup-claude-gateway.sh          # deploy + test
./scripts/setup-claude-gateway-daemon.sh   # install as systemd service
./scripts/setup-claude-heartbeat.sh        # AI health monitor every 30 min
```

**Key config vars** (`~/.config/claude-gateway/.env` on VM):

| Variable | Default | Purpose |
|----------|---------|---------|
| `ANTHROPIC_API_KEY` | required | Your Anthropic key |
| `CLAUDE_MODEL` | `claude-opus-4-6` | Model for chat + agent |
| `GATEWAY_API_KEY` | unset | Require Bearer token on all endpoints |
| `RATE_LIMIT_RPM` | `60` | Per-IP rate limit (0 = disabled) |
| `LOCAL_LLM_URL` | unset | Route `local`/`haiku/*` requests to on-device LLM |

See **[docs/claude-gateway.md](claude-gateway.md)** for full usage, examples, and architecture.

## On-device LLM (zero API cost)

Two options — both set `LOCAL_LLM_URL` so the gateway routes free to on-device:

```bash
# Option A: llama.cpp with ARM SVE (fastest, ~12–16 tok/s on 3B)
./scripts/setup-llama-sve.sh

# Option B: Ollama + Jellyfin + NGINX homelab stack
./scripts/setup-homelab.sh
```

See **[docs/local-llm-in-vm.md](local-llm-in-vm.md)**, **[docs/llama-server.md](llama-server.md)**, and **[docs/homelab.md](homelab.md)**.

## Next on the plan

See **[docs/next-on-plan.md](next-on-plan.md)** for remaining items: VNC desktop, hybrid NPU inference, Prometheus/Grafana monitoring, and 16KB pages.
