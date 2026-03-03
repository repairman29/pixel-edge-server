# OpenCode + Jarvis (Pixel VM)

OpenCode runs as a **headless server** in the Pixel VM so Jarvis can use it for coding tasks in a terminal/session.

## Service

- **Endpoint (inside VM):** `http://127.0.0.1:4096`
- **API spec:** `http://127.0.0.1:4096/doc`
- **Service:** `systemctl --user status opencode-serve`

## How Jarvis can use OpenCode

1. **CLI attach (recommended)**  
   From the VM, with `cwd` set to the target repo:
   ```bash
   opencode run --attach http://127.0.0.1:4096 "Your coding task in plain language"
   ```
   Use your normal exec tool with `workdir` set to the repo (e.g. `~/.openclaw/workspace/pixel-edge-server`).

2. **HTTP API**  
   For more control (create session, send message, get diff):
   - `GET /project`, `GET /session`, `POST /session/:id/message`, etc.
   - See `/doc` for the full OpenAPI spec.

3. **Health check**  
   `curl -s http://127.0.0.1:4096/global/health` → `{"healthy":true,"version":"..."}`

## One-time setup (in VM)

If OpenCode asks for config or auth:

```bash
opencode init
opencode auth login   # optional: add API keys for providers
```

Ensure `~/.opencode/bin` is on PATH when you run `opencode` (or use the full path).
