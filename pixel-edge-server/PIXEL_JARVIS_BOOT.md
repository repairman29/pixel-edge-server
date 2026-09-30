# Pixel Jarvis Boot

Use the official Proot JARVIS stack, but wrap it with one stable Termux entrypoint.

What this setup does:
- reads `~/.clawdbot/.env` for `DISCORD_BOT_TOKEN`
- removes `TELEGRAM_BOT_TOKEN` so Telegram stays off
- forces Discord on and Telegram off in `~/.clawdbot/clawdbot.json`
- sets `session.dmScope` to `per-channel-peer` for Discord DM replies
- sets the primary model to `groq/llama-3.1-8b-instant` so replies do not depend on the Pixel InferrLM app running on `127.0.0.1:8889`
- exports `TMPDIR=$HOME/tmp` so the Proot gateway does not crash trying to create `/tmp/clawdbot`
- starts the official Proot bootstrap script, cron, and a keepalive loop

Files:
- `pixel-jarvis-autoboot.sh` - canonical start/restart script
- `pixel-jarvis-keepalive.sh` - health check and self-heal wrapper
- `pixel-jarvis-supervisor.sh` - boot-friendly long-running supervisor

Recommended install on the Pixel:

```bash
cp ~/pixel-jarvis-autoboot.sh ~/pixel-jarvis-keepalive.sh ~/pixel-jarvis-supervisor.sh ~/
chmod +x ~/pixel-jarvis-autoboot.sh ~/pixel-jarvis-keepalive.sh ~/pixel-jarvis-supervisor.sh
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-jarvis <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
sleep 15
nohup "$HOME/pixel-jarvis-supervisor.sh" >> "$HOME/jarvis-boot.log" 2>&1 &
EOF
chmod +x ~/.termux/boot/start-jarvis
```

Notes:
- MacBook and Pixel can both use port `18789`; ports do not conflict across different hosts.
- If you want pure on-device inference later, turn the InferrLM server back on and switch the primary model away from Groq.
- After `session.dmScope` is enabled, the first DM creates a Discord session key automatically. The boot script will relink it to `agent:main:main` on later restarts when that alias exists.
- The supervisor replaces cron here, so it works even when `crontab` is not installed in Termux.
