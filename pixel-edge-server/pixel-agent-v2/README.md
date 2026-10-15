# pixel-agent-v2 (Rust)

Best-in-class Pixel agent: gateway + router + reflexive (Jarvis on device). **Runs on the Pixel** in Termux; the Mac is only for building and pushing the binary.

**Prerequisites:** Phase 1 done (Termux + Termux:API). See [GETTING_STARTED.md](../GETTING_STARTED.md). **Step-by-step:** [PHASE2_WORKING.md](../PHASE2_WORKING.md).

## Build and push (Mac → Pixel)

The Pixel runs **Linux (aarch64)**; a Mac build won’t run there. Use one of:

**A. Script (recommended)**, from `pixel-edge-server`:
```bash
./scripts/build-and-push-pixel.sh
```
Requires `cross` (`cargo install cross`) or a working `aarch64-unknown-linux-gnu` target + linker.

**B. Manual cross-compile**, in `pixel-agent-v2`:
```bash
cross build --release --target aarch64-unknown-linux-gnu
adb push target/aarch64-unknown-linux-gnu/release/pixel-agent-v2 /sdcard/jarvis/pixel-agent-v2
```
**C. Build in Termux**, push the project to the device, then in Termux: `pkg install rust -y`, `cd ~/pixel-agent-v2`, `cargo build --release`. Binary: `target/release/pixel-agent-v2`.

## Deploy and run on the Pixel

1. **Push the binary** (if you didn’t use the script): see paths above; destination `/sdcard/jarvis/pixel-agent-v2`.
2. **On the Pixel, in Termux:**
   ```bash
   cp /sdcard/jarvis/pixel-agent-v2 ~/pixel-agent-v2
   chmod +x ~/pixel-agent-v2
   ```
3. **Start Jarvis** on the Pixel (open the app so the HTTP API is listening on 9090). If the model doesn’t load at boot, you can try `curl -X POST http://127.0.0.1:9090/load-model` from Termux (same device), note this can crash the app on some devices.
4. **Run the gateway** in Termux:
   ```bash
   ./pixel-agent-v2
   ```
   Gateway listens on `127.0.0.1:18789` (loopback only; `adb forward` reaches it); it talks to Jarvis at `127.0.0.1:9090` on the same device.
5. **Chat** from the native app (when built) or from Termux: `curl -s -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'`

All runtime is on the Pixel: no Mac in the loop.

## Config (on device)

- **REFLEXIVE_URL**, default `http://127.0.0.1:9090` (Jarvis on same Pixel). Leave unset unless you point at another host.
- **REFLEXIVE_MODEL**, default `gemma-3b`; override if your backend expects a different model name.
- **PORT**, gateway listen port (default 18789).
- **BIND_HOST** (or `--bind <host>`), listen address, default `127.0.0.1`. Set `0.0.0.0` only on purpose: it exposes `/chat` on Wi-Fi / cellular / Tailscale, and the gateway prints a warning.

## 503 / Jarvis crashes

The on-device model load (at boot or via `/load-model`) can crash the app on some devices. The stack is **Jarvis on Pixel only** (no paid APIs, no Mac as LLM). Until the crash is fixed or another on-device option is added, chat will work only when Jarvis stays up with the model loaded.

## Optional: test from Mac with adb forward

To hit the gateway from your Mac while it runs on the Pixel: `adb forward tcp:18789 tcp:18789`, then `curl -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'`.

## Phases

- **Phase 2:** `/chat` → reflexive (Jarvis 9090 on Pixel). Pass test checkpoint.
- **Phase 3–5:** Heartbeat, outbox, memory, app, voice, see [BLUEPRINT_BEST_IN_CLASS.md](../BLUEPRINT_BEST_IN_CLASS.md).

## Python gateway (`server.py`)

`server.py` is the live Python edge gateway on :18790 (stdlib only, runs in Termux). It is the
single home of the gateway: Froogle's `launch/scripts/pixel_gateway.py` was a fork and is now a
shim that execs this file. The full security contract and every env var are in the module
docstring. Short version:

- Binds `127.0.0.1` by default (`BIND_HOST`). `adb forward tcp:18790 tcp:18790` lands on the
  phone's loopback, so that is all adb needs.
- Host and Origin checks, JSON-only POSTs, no CORS, input validation, no `shell=True`,
  SMS rate limit (`SMS_RATE_PER_MIN`, default 10).
- Bearer token, OFF by default. The token is `GATEWAY_TOKEN` if set, else the contents of
  `GATEWAY_TOKEN_FILE` (default `~/.config/pixel-gateway/token`, whitespace stripped). If
  neither exists, auth stays off. When on, every route except `GET /` and `GET /health` needs
  `Authorization: Bearer <token>` (compared with `hmac.compare_digest`), and every Mac caller
  must send it. That covers `/telemetry`, `/inbound/sms` + `/sms/inbox`, `/inbound/sync`,
  `/chat`, `/v1/chat/completions` and every `/actuate/*` route (sms, camera, torch, vibrate).
  `GET /health` stays open and reports `"auth": "bearer"` or `"off"`; with auth on it shows
  battery, storage and uptime only to a caller that sends the token. To turn auth on:
  `mkdir -p ~/.config/pixel-gateway && head -c 32 /dev/urandom | base64 > ~/.config/pixel-gateway/token && chmod 600 ~/.config/pixel-gateway/token`. No restart needed: the file is re-read on every request.
- Camera output is confined to `CAMERA_DIRS` (default `/sdcard`), `.jpg`/`.jpeg` names only.
- `/inbound/sync` posts only to `INBOUND_SYNC_URL` (default `http://127.0.0.1:8795/incoming`).

Tests run on the Mac with every Termux call mocked: `pytest -q tests/`.
