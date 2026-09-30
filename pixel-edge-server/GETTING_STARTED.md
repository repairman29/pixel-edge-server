# Getting started: best-in-class Pixel agent

Follow the blueprint phase-by-phase. **Phase 1 first** — pass its test checkpoint before touching the Rust agent.

---

## Phase 1: Infrastructure (do this first)

### One-shot setup via ADB (recommended)

On your **Mac**, with the Pixel connected via USB and **USB debugging** on:

```bash
cd pixel-edge-server
./scripts/setup_phase1_adb.sh
```

This script will:
1. Apply the **phantom process bypass** (so the agent is less likely to be killed).
2. Download and install **Termux** (GitHub arm64 build) via `adb install`.
3. Optionally install **Termux + Termux:API** from F-Droid (same signer) if you choose; if your device blocks non-Play installs, install both from the F-Droid app on the Pixel instead.
4. Print verification steps.

If any install fails with `INSTALL_FAILED_VERIFICATION_FAILURE`, enable **Install via USB** (Developer options) or install Termux and Termux:API from the F-Droid app on the device.

### Manual steps (if you prefer)

- **Phantom bypass only:** `./scripts/phantom_bypass.sh`
- **Termux:** Install from [F-Droid](https://f-droid.org/en/packages/com.termux/) or [GitHub](https://github.com/termux/termux-app/releases). Do **not** use the Play Store version.
- **Termux:API:** Install from [F-Droid](https://f-droid.org/en/packages/com.termux.api/). Must match Termux’s signer (use F-Droid for both).

### Verify Phase 1 (test checkpoint)

In **Termux** on the device:

```bash
pkg update -y && pkg install -y termux-api
termux-battery-status
```

If `termux-battery-status` prints JSON, **Phase 1 is done.** Move on to Phase 2.

---

## Phase 2: Rust agent + gateway on the Pixel

Everything runs on the Pixel; the Mac is only for building (for Linux aarch64) and pushing.

### Step 1: Build for Pixel and push (on Mac)

You must build for **aarch64 Linux** (Termux), not for Mac. Easiest:

```bash
cd pixel-edge-server
./scripts/build-and-push-pixel.sh
```

If that fails, install cross-compile: `cargo install cross`, then run the script again. Or see [pixel-agent-v2/README.md](pixel-agent-v2/README.md) for manual cross-compile or building inside Termux.

### Step 2: On the Pixel (Termux)

```bash
cp /sdcard/jarvis/pixel-agent-v2 ~/pixel-agent-v2 && chmod +x ~/pixel-agent-v2
```

Start the **Jarvis** app so it listens on 9090 (skip `/load-model` if it crashes the app). Then:

```bash
./pixel-agent-v2
```

You should see: `Gateway listening on http://0.0.0.0:18789`.

### Step 3: Test checkpoint

In **another Termux session** (or same after backgrounding the gateway with Ctrl+Z then `bg`), or from the app when built:

```bash
curl -s -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'
```

- If Jarvis is up with the model loaded: you get a real reply.
- If Jarvis is down or 503: you get a clear error (gateway is still working).

**Full checklist:** [PHASE2_WORKING.md](PHASE2_WORKING.md).

See [pixel-agent-v2/README.md](pixel-agent-v2/README.md) and [BLUEPRINT_BEST_IN_CLASS.md](BLUEPRINT_BEST_IN_CLASS.md) for Phase 3–5.

---

## Quick reference

| Phase | Focus            | Test checkpoint |
|-------|------------------|-----------------|
| 1     | Infrastructure   | Termux + `termux-api` work; scripts exist |
| 2     | Routing + LLMs + gateway | One request → one LLM response |
| 3     | Heartbeat + outbox | One heartbeat run → message in outbox and sent |
| 4     | Memory           | 6+ turns → prompt has recent + summary |
| 5     | Remote + app + voice | App chat works; Tailscale; Mission Control if wired |

**Rule:** Don’t start the next phase until the current phase’s test checkpoint passes.
