# Pixel 8 Pro agent stack (current)

**Best-in-class build-from-scratch design:** See [BLUEPRINT_BEST_IN_CLASS.md](BLUEPRINT_BEST_IN_CLASS.md) for the full custom agent (Bicameral Mind, heartbeat, memory, Mission Control). The minimal **pixel-agent** below is a stopgap; the blueprint defines the target stack and `pixel-agent-v2/` layout.

## Why we pivoted

- **OpenClaw on device**: Install script fails on Termux (unsupported OS). `npm install -g openclaw` fails on the **koffi** native build. Not viable on the Pixel.
- **ZeroClaw-Android**: [Archived](https://github.com/Natfii/ZeroClaw-Android) Mar 7, 2026. No longer maintained.
- **DroidClaw**: Hosted dashboard/features are paid (~$40). We're **building our own** instead.

## Current on-device stack: build our own

| Component | Role |
|-----------|------|
| **pixel-agent** | **Our own** minimal agent: Python in Termux, Telegram + Jarvis HTTP API (9090) + `!shell` tool. No OpenClaw, no koffi, no subscription. Code: [pixel-agent/](pixel-agent/). |
| **Jarvis app** | HTTP API on port 9090 (on-device Gemma or fallback). Start Jarvis first so the agent can call it. Use the same bot token in only one place (Jarvis Telegram or pixel-agent) to avoid 409. |
| **Termux** | Runs pixel-agent (`python3 agent.py`). `pkg install python pip` then `pip install -r requirements.txt`. |
| **Tailscale** | Remote access; later for "other bots talk to Pixel" if we add an HTTP endpoint. |

## Quick start: pixel-agent

1. **On Mac**: Push the agent to the device: `adb push pixel-edge-server/pixel-agent /sdcard/jarvis/pixel-agent`
2. **In Termux**: `cp -r /sdcard/jarvis/pixel-agent ~/pixel-agent && cd ~/pixel-agent` then `pkg install python pip -y`, `pip install -r requirements.txt`, `export TELEGRAM_TOKEN="your_bot_token"`, `python3 agent.py`
3. **Jarvis app**: Start it (START JARVIS) so 9090 is up. If you use this bot token in pixel-agent, don't start the Telegram bot in the Jarvis app (or use a different token there).

See [pixel-agent/README.md](pixel-agent/README.md) for details and extending (more tools, heartbeat, other LLM URLs).

## DroidClaw (optional, paid)

- DroidClaw APK is still installed if you want UI automation (control the phone by tapping/typing). The hosted dashboard at [app.droidclaw.ai](https://app.droidclaw.ai) is paid (~$40). You can uninstall the app if you're not using it.
- For Telegram + LLM chat we use **pixel-agent** (our own) or the Jarvis app, not DroidClaw.

## Optional: Android 14 phantom process limit

If the agent or Termux gets killed under load, you can raise the background process limit via ADB (see alternatives blueprint). Only if needed.
