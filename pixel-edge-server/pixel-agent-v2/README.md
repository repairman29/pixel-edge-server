# pixel-agent-v2 (Rust)

Best-in-class Pixel agent: gateway + router + reflexive (Jarvis on device). **Runs on the Pixel** in Termux; the Mac is only for building and pushing the binary.

**Prerequisites:** Phase 1 done (Termux + Termux:API). See [GETTING_STARTED.md](../GETTING_STARTED.md). **Step-by-step:** [PHASE2_WORKING.md](../PHASE2_WORKING.md).

## Build and push (Mac → Pixel)

The Pixel runs **Linux (aarch64)**; a Mac build won’t run there. Use one of:

**A. Script (recommended)** — from `pixel-edge-server`:
```bash
./scripts/build-and-push-pixel.sh
```
Requires `cross` (`cargo install cross`) or a working `aarch64-unknown-linux-gnu` target + linker.

**B. Manual cross-compile** — in `pixel-agent-v2`:
```bash
cross build --release --target aarch64-unknown-linux-gnu
adb push target/aarch64-unknown-linux-gnu/release/pixel-agent-v2 /sdcard/jarvis/pixel-agent-v2
```
**C. Build in Termux** — push the project to the device, then in Termux: `pkg install rust -y`, `cd ~/pixel-agent-v2`, `cargo build --release`. Binary: `target/release/pixel-agent-v2`.

## Deploy and run on the Pixel

1. **Push the binary** (if you didn’t use the script): see paths above; destination `/sdcard/jarvis/pixel-agent-v2`.
2. **On the Pixel, in Termux:**
   ```bash
   cp /sdcard/jarvis/pixel-agent-v2 ~/pixel-agent-v2
   chmod +x ~/pixel-agent-v2
   ```
3. **Start Jarvis** on the Pixel (open the app so the HTTP API is listening on 9090). If the model doesn’t load at boot, you can try `curl -X POST http://127.0.0.1:9090/load-model` from Termux (same device) — note this can crash the app on some devices.
4. **Run the gateway** in Termux:
   ```bash
   ./pixel-agent-v2
   ```
   Gateway listens on `0.0.0.0:18789`; it talks to Jarvis at `127.0.0.1:9090` on the same device.
5. **Chat** from the native app (when built) or from Termux: `curl -s -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'`

All runtime is on the Pixel: no Mac in the loop.

## Config (on device)

- **REFLEXIVE_URL** — default `http://127.0.0.1:9090` (Jarvis on same Pixel). Leave unset unless you point at another host.
- **REFLEXIVE_MODEL** — default `gemma-3b`; override if your backend expects a different model name.
- **PORT** — gateway listen port (default 18789).

## 503 / Jarvis crashes

The on-device model load (at boot or via `/load-model`) can crash the app on some devices. The stack is **Jarvis on Pixel only** (no paid APIs, no Mac as LLM). Until the crash is fixed or another on-device option is added, chat will work only when Jarvis stays up with the model loaded.

## Optional: test from Mac with adb forward

To hit the gateway from your Mac while it runs on the Pixel: `adb forward tcp:18789 tcp:18789`, then `curl -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'`.

## Phases

- **Phase 2:** `/chat` → reflexive (Jarvis 9090 on Pixel). Pass test checkpoint.
- **Phase 3–5:** Heartbeat, outbox, memory, app, voice — see [BLUEPRINT_BEST_IN_CLASS.md](../BLUEPRINT_BEST_IN_CLASS.md).
