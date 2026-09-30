# Get Phase 2 working (gateway + Jarvis on Pixel)

Follow this checklist so the gateway runs on the Pixel and chat works (or returns a clear error when Jarvis is down).

## Prerequisites

- **Phase 1 done:** Termux + Termux:API on the Pixel; `termux-battery-status` works.
- **Mac:** Rust installed, device connected via USB, USB debugging on.
- **Jarvis app** installed on the Pixel (from jarvis-android).

---

## 1. Build for Pixel and push (Mac)

The binary must be **Linux aarch64** for Termux. From your Mac:

```bash
cd /Users/jeffadkins/Projects/pixel-edge-server
./scripts/build-and-push-pixel.sh
```

- **If the script fails** (no cross-compile): run `cargo install cross`, then run the script again.
- **If you don’t use Docker:** see pixel-agent-v2/README.md for “Build in Termux” (build the Rust project on the device).

---

## 2. On the Pixel: copy binary and install deps (Termux)

In Termux:

```bash
cp /sdcard/jarvis/pixel-agent-v2 ~/pixel-agent-v2
chmod +x ~/pixel-agent-v2
pkg install -y curl
```

---

## 3. Start Jarvis (Pixel app)

- Open the **Jarvis** app on the Pixel.
- Let it start (HTTP API on 9090). Do **not** call `/load-model` if that has crashed the app before.

---

## 4. Run the gateway (Termux)

In Termux:

```bash
./pixel-agent-v2
```

Expected: `Gateway listening on http://0.0.0.0:18789`. Leave this running.

---

## 5. Test (Termux or app)

**From Termux:** open a new session (or use `tmux`/split), then:

```bash
curl -s -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'
```

- **Success:** JSON with `"reply":"..."` from Jarvis (or an error string if Jarvis is 503 / not loaded).
- **Gateway working:** you get a response; if it’s `[Error: ...]` about Jarvis, the gateway itself is fine and the next step is fixing Jarvis model load.

---

## Troubleshooting

| Issue | What to do |
|-------|------------|
| `./build-and-push-pixel.sh` fails | Install cross: `cargo install cross`. Or build in Termux (see README). |
| Binary not found in Termux | Run step 2 again; check `ls -la ~/pixel-agent-v2`. |
| `curl: command not found` | In Termux: `pkg install -y curl`. |
| `[Error: Jarvis unreachable]` | Start the Jarvis app; it must listen on 9090. |
| `[Error: Jarvis returned 503 Model not loaded]` | Jarvis is up but the model isn’t loaded. On some devices `/load-model` crashes the app; until that’s fixed, the gateway works but chat returns 503. |

---

Phase 2 is **done** when one HTTP request to the gateway returns one response (reply or clear error). Then move on to Phase 3 (heartbeat + outbox) per the blueprint.
