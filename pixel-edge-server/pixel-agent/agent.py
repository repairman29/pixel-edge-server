#!/usr/bin/env python3
"""
Minimal Pixel agent: Telegram + Jarvis HTTP API (9090) + shell tool.
Run in Termux. Set TELEGRAM_TOKEN and optionally JARVIS_URL (default 127.0.0.1:9090).
Only one process should use the bot token (disable Telegram in Jarvis app if this runs).
"""
import os
import subprocess
import logging
from typing import Optional

import requests
from telegram import Update
from telegram.ext import Application, ContextTypes, CommandHandler, MessageHandler, filters

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("pixel_agent")

JARVIS_URL = os.environ.get("JARVIS_URL", "http://127.0.0.1:9090")
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "").strip()
MAX_SHELL_OUTPUT = 2000


def jarvis_chat(user_message: str, system: Optional[str] = None) -> str:
    """Call Jarvis HTTP API (OpenAI-compatible)."""
    url = f"{JARVIS_URL.rstrip('/')}/v1/chat/completions"
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user_message})
    try:
        r = requests.post(
            url,
            json={
                "model": "gemma-3b",
                "messages": messages,
                "max_tokens": 1024,
            },
            timeout=60,
        )
        r.raise_for_status()
        data = r.json()
        choice = data.get("choices", [{}])[0]
        return (choice.get("message") or {}).get("content", "").strip() or "[No response]"
    except requests.exceptions.RequestException as e:
        return f"[Jarvis error: {e}]"


def run_shell(cmd: str) -> str:
    """Run a shell command, return truncated output."""
    try:
        out = subprocess.run(
            ["sh", "-c", cmd],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=os.environ.get("HOME", "/data/data/com.termux/files/home"),
        )
        text = (out.stdout or "").strip() or (out.stderr or "").strip()
        return (text[:MAX_SHELL_OUTPUT] + "..." if len(text) > MAX_SHELL_OUTPUT else text) or "(no output)"
    except subprocess.TimeoutExpired:
        return "(timeout)"
    except Exception as e:
        return f"(error: {e})"


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "Pixel agent here. Send a message for a reply from Jarvis (on-device LLM). "
        "Use !shell <cmd> to run a command."
    )


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    try:
        r = requests.get(f"{JARVIS_URL.rstrip('/')}/health", timeout=5)
        data = r.json() if r.ok else {}
        ready = data.get("ready", False)
        await update.message.reply_text(f"Jarvis: {'ready' if ready else 'not ready'} | URL: {JARVIS_URL}")
    except Exception as e:
        await update.message.reply_text(f"Jarvis: unreachable — {e}")


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = (update.message.text or "").strip()
    if not text:
        return

    # !shell <command>
    if text.lower().startswith("!shell "):
        cmd = text[7:].strip()
        if not cmd:
            await update.message.reply_text("Usage: !shell <command>")
            return
        result = run_shell(cmd)
        await update.message.reply_text(f"```\n{result}\n```", parse_mode="Markdown")
        return

    # Normal message -> Jarvis
    await update.message.chat.send_action("typing")
    reply = jarvis_chat(text)
    await update.message.reply_text(reply)


def main() -> None:
    if not TELEGRAM_TOKEN:
        log.error("Set TELEGRAM_TOKEN in the environment")
        raise SystemExit(1)
    app = Application.builder().token(TELEGRAM_TOKEN).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    log.info("Pixel agent running; Jarvis URL=%s", JARVIS_URL)
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
