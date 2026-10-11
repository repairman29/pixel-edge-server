# Pixel agent (our own)

Minimal Telegram + LLM agent that runs in Termux. Uses the **Jarvis app** HTTP API (port 9090) for chat and runs shell commands via `!shell`. No OpenClaw, no koffi, no paid services.

## Prerequisites

- **Jarvis app** running on the Pixel (START JARVIS) so port 9090 is up.
- **Termux** (F-Droid). Python 3 and pip.
- **One** Telegram bot token. If the Jarvis app already uses it, stop the Jarvis Telegram bot (or use a second bot token for this agent) to avoid 409 conflicts.

## Setup in Termux

```bash
pkg update && pkg install python pip
cd ~/pixel-agent   # or copy pixel-agent/ from repo to device
pip install -r requirements.txt
export TELEGRAM_TOKEN="your_bot_token"
export JARVIS_URL="http://127.0.0.1:9090"   # default
python3 agent.py
```

To push this folder to the device (from Mac, with Pixel connected):

```bash
adb push pixel-edge-server/pixel-agent /sdcard/jarvis/pixel-agent
# In Termux: cp -r /sdcard/jarvis/pixel-agent ~/pixel-agent && cd ~/pixel-agent
```

## Usage

- **/start**, Short help.
- **/status**, Check if Jarvis HTTP API is reachable.
- **!shell &lt;cmd&gt;**, Run a shell command in Termux (e.g. `!shell ls ~`).
- **Any other message**, Sent to Jarvis (on-device LLM) and the reply is sent back.

## Running in the background

```bash
nohup python3 agent.py > agent.log 2>&1 &
```

Or use `termux-boot` and a script in `~/.termux/boot/` to start on Termux launch.

## Extending

- Add more tools in `agent.py` (e.g. read_file, list_dir) and call them from a simple parser or let the LLM return structured commands.
- Add a heartbeat loop (cron or loop with sleep) that checks state and writes to an outbox for proactive messages.
- Point `JARVIS_URL` at another OpenAI-compatible endpoint (e.g. Ollama, cloud) if you don’t use the Jarvis app.
