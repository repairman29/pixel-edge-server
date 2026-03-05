# Available Tools for Pixel Jarvis

Tools and skills ClawdBot can use on the Pixel 8 Pro.

---

## Android System Tools

**Skill:** `android-system` (built-in)

| Tool | When to use |
|------|--------------|
| `adb_shell` | Run shell commands on Pixel via ADB |
| `launch_app` | "open Chrome", "launch Settings" |
| `app_info` | "what apps are installed", "app version" |
| `device_info` | "battery level", "CPU usage", "storage info" |
| `system_control` | "enable airplane mode", "toggle WiFi" |

---

## File Management

**Skill:** `file-manager` (built-in)

| Tool | When to use |
|------|-------------|
| `list_files` | "show files in Downloads", "list /sdcard/" |
| `read_file` | "read that file", "show file contents" |
| `write_file` | "create a note", "save this text" |
| `file_search` | "find PDF files", "search for images" |

---

## Network Tools

**Skill:** `network` (built-in)

| Tool | When to use |
|------|-------------|
| `http_get` | "fetch that URL", "download file" |
| `ping` | "ping google.com", "check connectivity" |
| `speed_test` | "run speed test", "check network speed" |

---

## Calculator

**Skill:** `calculator` (built-in)

| Tool | When to use |
|------|-------------|
| `quick_calc` | "15% of 240", "5 miles to km" |
| `unit_convert` | "convert Celsius to Fahrenheit" |
| `math_eval` | "sqrt(144)", "sin(90 degrees)" |

---

## Background Agents

**Skill:** `multi-agent` (built-in)

| Tool | When to use |
|------|-------------|
| `spawn_agent` | Long-running tasks, research, analysis |
| `agent_status` | "check background tasks", "what's running" |
| `agent_result` | "get results", "show background output" |

---

## Telegram Tools

**Skill:** `telegram` (built-in)

| Tool | When to use |
|------|-------------|
| `send_message` | Reply to user, send notifications |
| `get_chat_info` | "who am I talking to", "chat details" |
| `telegram_search` | "find previous messages", "search chat history" |

---

## Usage Rules

- **Always call the appropriate tool** when the user asks for something it can handle
- **Summarize the result** after using a tool
- **Don't hallucinate** - if you don't have a tool, say so
- **Prefer tools over descriptions** - actually do things, don't just talk about them