# Claude Gateway v2 — Pixel AI Server

Turn your Pixel 8 Pro into a **real AI server** backed by Claude Opus 4.6. The gateway
runs inside the Debian VM and is reachable from anywhere via Tailscale.

| Endpoint | Description |
|----------|-------------|
| `GET  /health` | Liveness probe + live metrics summary |
| `GET  /metrics` | Prometheus-format scrape endpoint |
| `GET  /v1/models` | List available models (+ local LLM if configured) |
| `POST /v1/chat/completions` | OpenAI-compatible chat — streaming and non-streaming |
| `POST /v1/agent` | Agentic task — Claude uses 9 built-in tools autonomously |
| `POST /v1/agent/stream` | Same as `/v1/agent` but streams turn-by-turn via SSE |

**Port:** `3456`
**Access:** `http://100.78.73.64:3456` (Tailscale) or `http://10.1.10.29:3456` (LAN)

---

## Quick Setup

```bash
# 1. Export your Anthropic API key
export ANTHROPIC_API_KEY=sk-ant-...

# 2. Deploy gateway to VM (copies files, npm install, smoke-test)
./scripts/setup-claude-gateway.sh

# 3. Install as persistent systemd daemon
./scripts/setup-claude-gateway-daemon.sh

# 4. (Optional) Install AI heartbeat — Claude monitors itself every 30 min
./scripts/setup-claude-heartbeat.sh

# 5. (Optional) Build local LLM for haiku/free requests
./scripts/setup-llama-sve.sh
```

---

## Environment & Configuration

**File on VM:** `~/.config/claude-gateway/.env`

```env
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_GATEWAY_PORT=3456
CLAUDE_MODEL=claude-opus-4-6

# Optional: require Bearer token for all non-health endpoints
# GATEWAY_API_KEY=your-secret-token

# Optional: rate limit per IP (default 60 req/min, 0 = disabled)
# RATE_LIMIT_RPM=60

# Optional: route haiku/local model requests to a local LLM instead of Claude API
# LOCAL_LLM_URL=http://127.0.0.1:8080/v1/chat/completions  # llama-server
# LOCAL_LLM_URL=http://127.0.0.1:11434/v1/chat/completions # Ollama
```

---

## Chat API — OpenAI-compatible

Point any OpenAI SDK or tool at your Pixel:

```bash
export OPENAI_BASE_URL=http://100.78.73.64:3456/v1
export OPENAI_API_KEY=dummy   # handled server-side via ANTHROPIC_API_KEY
```

**Streaming:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-opus-4-6",
    "stream": true,
    "messages": [
      {"role": "system", "content": "You are a concise assistant."},
      {"role": "user",   "content": "What is the Tensor G3?"}
    ]
  }' | grep -o '"content":"[^"]*"' | sed 's/"content":"//;s/"//'
```

**Non-streaming:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello from my Pixel server!"}]}' \
  | jq '.choices[0].message.content'
```

**Local LLM routing** — use model `"local"` to route to `LOCAL_LLM_URL` instead of Claude API:

```bash
curl -s -X POST http://100.78.73.64:3456/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"local","messages":[{"role":"user","content":"Hi!"}],"max_tokens":128}'
```

**Python (openai SDK):**

```python
from openai import OpenAI

client = OpenAI(base_url="http://100.78.73.64:3456/v1", api_key="dummy")
response = client.chat.completions.create(
    model="claude-opus-4-6",
    messages=[{"role": "user", "content": "Summarize the Pixel 8 Pro specs."}],
)
print(response.choices[0].message.content)
```

---

## Agent API — Autonomous Task Execution

Submit any task and Claude autonomously executes it using 9 built-in tools:

| Tool | What it does |
|------|-------------|
| `run_shell` | Execute any bash command in the Debian VM |
| `read_file` | Read a file (supports `~/` paths; tail semantics for logs) |
| `write_file` | Write content to a file (creates parent dirs automatically) |
| `restart_service` | Restart a systemd user service by name |
| `http_fetch` | GET or POST any URL reachable from the VM |
| `check_thermal` | Read all `/sys/class/thermal` zones |
| `check_disk` | `df -h` output |
| `list_processes` | Top 20 CPU consumers |
| `check_network` | Open ports + network interfaces |

**Health check:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{"task":"Check thermals, disk, and open ports. Summarize health in 3 bullets."}' \
  | jq -r '.result'
```

**Read a log file:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{"task":"Read the last 50 lines of ~/claude-gateway/heartbeat.log and summarize findings."}' \
  | jq -r '.result'
```

**Restart a failed service:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{"task":"Check if claude-gateway service is running. If not, restart it and confirm."}' \
  | jq '{turns:.turns, result:.result}'
```

**Write a file:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{"task":"Write a brief server status report to ~/status.txt, then read it back."}' \
  | jq -r '.result'
```

---

## Streaming Agent API

`POST /v1/agent/stream` — identical task format to `/v1/agent` but returns SSE events:

| Event type | Payload |
|-----------|---------|
| `start` | `{ task, model, timestamp }` |
| `turn_start` | `{ turn: N }` |
| `text` | `{ text: "..." }` — Claude thinking or responding |
| `tool_call` | `{ name, input }` — tool Claude decided to invoke |
| `tool_running` | `{ name }` — tool execution in progress |
| `tool_result` | `{ name, result }` — truncated tool output |
| `done` | `{ result, turns, model, timestamp }` |

**Example — watch Claude work in real time:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent/stream \
  -H "Content-Type: application/json" \
  -d '{"task":"Investigate the server: check thermal, disk, and running services."}' \
  | while IFS= read -r line; do
      echo "$line" | grep '^data:' | sed 's/^data: //' | jq -r '
        if .type == "tool_call" then "  [TOOL] \(.name): \(.input | tostring | .[0:80])"
        elif .type == "tool_result" then "  [RESULT] \(.result | .[0:120])"
        elif .type == "text" then "  [TEXT] \(.text)"
        elif .type == "done" then "\n=== DONE (\(.turns) turns) ===\n\(.result)"
        else empty end' 2>/dev/null
    done
```

---

## Metrics — Prometheus scrape

`GET /metrics` returns Prometheus-format metrics, no auth required:

```bash
curl http://100.78.73.64:3456/metrics
```

```
claude_gateway_uptime_seconds 3600.0
claude_gateway_requests_total 142
claude_gateway_requests_errors_total 2
claude_gateway_active_connections 1
claude_gateway_tokens_in_total 284932
claude_gateway_tokens_out_total 71203
claude_gateway_agent_turns_total 89
claude_gateway_local_llm_requests_total 14
```

Add to a Prometheus `scrape_config` if you run Prometheus anywhere on your network:

```yaml
- job_name: pixel_gateway
  static_configs:
    - targets: ['100.78.73.64:3456']
```

---

## AI Heartbeat

Claude runs every 30 minutes, inspects your server autonomously, and logs a report:

```
[2026-03-05 04:00:01] Submitting health task to Claude (model: claude-opus-4-6)...
[2026-03-05 04:01:43] Heartbeat complete (8 agent turns).

HEARTBEAT REPORT
  STATUS: OK
  Summary: All services healthy, thermals nominal, no runaway processes.
  • claude-gateway: active (running)
  • openclaw: active (running)
  • Max thermal: cpu-thermal=52.3°C (within limits)
  • Disk: 4.1G used / 29G (14%) — ample space
  • No process above 5% CPU
  • Ports 3456 and 18789 are listening
```

```bash
# Read latest report
ssh -p 8022 droid@100.78.73.64 'tail -60 ~/claude-gateway/heartbeat.log'
```

---

## Useful Commands

```bash
# Health probe from Mac
curl http://100.78.73.64:3456/health | jq

# Prometheus metrics
curl http://100.78.73.64:3456/metrics

# Daemon status
ssh -p 8022 droid@100.78.73.64 'systemctl --user status claude-gateway'

# Follow logs
ssh -p 8022 droid@100.78.73.64 'journalctl --user -u claude-gateway -f'

# Restart
ssh -p 8022 droid@100.78.73.64 'systemctl --user restart claude-gateway'

# Change model to Sonnet (cheaper, still great)
ssh -p 8022 droid@100.78.73.64 \
  "sed -i 's/CLAUDE_MODEL=.*/CLAUDE_MODEL=claude-sonnet-4-6/' ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"

# Enable Bearer auth
ssh -p 8022 droid@100.78.73.64 \
  "echo 'GATEWAY_API_KEY=mysecret' >> ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"

# Route local/haiku to llama-server (after setup-llama-sve.sh)
ssh -p 8022 droid@100.78.73.64 \
  "echo 'LOCAL_LLM_URL=http://127.0.0.1:8080/v1/chat/completions' >> ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"
```

---

## Architecture

```
Mac / anywhere
     │
     │  Tailscale (encrypted)
     ▼
Pixel 8 Pro (100.78.73.64)
     │
     │  SSH / TCP :3456
     ▼
Debian VM
  ├── claude-gateway  :3456          ← this service (Node.js)
  │     ├── /health                  ← liveness + live metrics
  │     ├── /metrics                 ← Prometheus scrape
  │     ├── /v1/models
  │     ├── /v1/chat/completions     ← OpenAI-compat chat
  │     ├── /v1/agent                ← agentic tasks (9 tools)
  │     └── /v1/agent/stream         ← streaming agent (SSE)
  │
  ├── llama-server    :8080  (optional, via setup-llama-sve.sh)
  ├── Ollama          :11434 (optional, via homelab/docker-compose.yml)
  ├── Jellyfin        :8096  (optional, via homelab/docker-compose.yml)
  ├── NGINX           :80    (optional, reverse proxy for above)
  ├── OpenClaw        :18789
  └── OpenCode        :4096

Claude API (api.anthropic.com)
  └── Opus 4.6 / Sonnet 4.6 / Haiku 4.5 — cloud inference
```
