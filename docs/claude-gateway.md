# Claude Gateway — Pixel AI Server

Turn your Pixel 8 Pro into a **real AI server** backed by Claude Opus 4.6. The gateway
runs inside the Debian VM and exposes two APIs accessible from anywhere via Tailscale:

| API | Description |
|-----|-------------|
| `POST /v1/chat/completions` | OpenAI-compatible chat — drop-in replacement for any OpenAI SDK client |
| `POST /v1/agent` | Agentic task endpoint — Claude autonomously uses shell, thermal, disk, network tools on your Pixel |
| `GET  /v1/models` | List available Claude models |
| `GET  /health` | Liveness probe |

**Port:** `3456`
**Access:** `http://100.78.73.64:3456` (Tailscale) or `http://10.1.10.29:3456` (LAN)

---

## Quick Setup

```bash
# 1. Export your Anthropic API key locally
export ANTHROPIC_API_KEY=sk-ant-...

# 2. Deploy to the VM (copies files, npm install, smoke-test)
./scripts/setup-claude-gateway.sh

# 3. Install as persistent systemd daemon
./scripts/setup-claude-gateway-daemon.sh

# 4. (Optional) Install AI heartbeat — Claude monitors itself every 30 min
./scripts/setup-claude-heartbeat.sh
```

---

## Chat API — OpenAI-compatible

Point any OpenAI SDK or tool at your Pixel:

```bash
export OPENAI_BASE_URL=http://100.78.73.64:3456/v1
export OPENAI_API_KEY=dummy     # auth is handled server-side via ANTHROPIC_API_KEY
```

**Streaming example:**

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

**Non-streaming example:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello from my Pixel server!"}],
    "max_tokens": 256
  }' | jq '.choices[0].message.content'
```

**Python (openai SDK):**

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://100.78.73.64:3456/v1",
    api_key="dummy",
)

response = client.chat.completions.create(
    model="claude-opus-4-6",
    messages=[{"role": "user", "content": "Summarize the Pixel 8 Pro specs."}],
)
print(response.choices[0].message.content)
```

---

## Agent API — Autonomous Task Execution

Submit any task and Claude will autonomously execute it using tools native to the Pixel VM:

| Tool | What it does |
|------|-------------|
| `run_shell` | Execute any bash command in the Debian VM |
| `check_thermal` | Read all `/sys/class/thermal` zones |
| `check_disk` | `df -h` output |
| `list_processes` | Top 20 CPU consumers |
| `check_network` | Open ports + network interfaces |

**Example — server health check:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{
    "task": "Check thermal temps, disk usage, and list open ports. Summarize the Pixel server health in 3 bullet points."
  }' | jq -r '.result'
```

**Example — autonomous investigation:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{
    "task": "Find which process is consuming the most CPU and memory. Check if Docker is running and list active containers. Report everything in a concise summary."
  }' | jq '{turns: .turns, result: .result}'
```

**Example — custom system prompt:**

```bash
curl -s -X POST http://100.78.73.64:3456/v1/agent \
  -H "Content-Type: application/json" \
  -d '{
    "system": "You are a security auditor. Be terse and technical.",
    "task": "List all listening TCP ports and check for any unexpected services."
  }' | jq -r '.result'
```

**Python example:**

```python
import requests

r = requests.post("http://100.78.73.64:3456/v1/agent", json={
    "task": "How many CPU cores does the Pixel VM see? What is the CPU governor?",
})
print(r.json()["result"])
```

---

## AI Heartbeat

Once `setup-claude-heartbeat.sh` is run, Claude runs every 30 minutes, inspects your
Pixel server autonomously, and logs a structured health report:

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

**Read the latest report:**

```bash
ssh -p 8022 droid@100.78.73.64 'tail -60 ~/claude-gateway/heartbeat.log'
```

---

## Environment & Configuration

**File on VM:** `~/.config/claude-gateway/.env`

```env
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_GATEWAY_PORT=3456
CLAUDE_MODEL=claude-opus-4-6
```

To change the model (e.g. to Haiku for lower cost):

```bash
ssh -p 8022 droid@100.78.73.64 \
  "sed -i 's/CLAUDE_MODEL=.*/CLAUDE_MODEL=claude-haiku-4-5/' ~/.config/claude-gateway/.env"
ssh -p 8022 droid@100.78.73.64 'systemctl --user restart claude-gateway'
```

---

## Useful Commands

```bash
# Check daemon status
ssh -p 8022 droid@100.78.73.64 'systemctl --user status claude-gateway'

# Follow logs
ssh -p 8022 droid@100.78.73.64 'journalctl --user -u claude-gateway -f'

# Health probe from Mac
curl http://100.78.73.64:3456/health | jq

# Restart gateway
ssh -p 8022 droid@100.78.73.64 'systemctl --user restart claude-gateway'

# Update API key
ssh -p 8022 droid@100.78.73.64 \
  "sed -i 's/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=NEW_KEY/' ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"
```

---

## Architecture

```
Mac / anywhere
     │
     │  HTTPS (Tailscale)
     ▼
Pixel 8 Pro (100.78.73.64)
     │
     │  SSH / TCP
     ▼
Debian VM (port 8022)
  ├── claude-gateway (port 3456)     ← this service
  │     ├── /v1/chat/completions     ← OpenAI-compatible chat
  │     └── /v1/agent               ← agentic tasks + shell tools
  ├── OpenClaw / Mission Control (port 18789)
  ├── OpenCode (port 4096)
  └── Ollama / local LLM (port 11434, optional)
```

Claude Gateway forwards AI requests to `api.anthropic.com` via the Pixel's internet
connection. All inference runs in the cloud on Anthropic's infrastructure; the Pixel
handles orchestration, tool execution, and local system access.
