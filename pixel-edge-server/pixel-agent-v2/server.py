#!/usr/bin/env python3
"""pixel-agent-v2 gateway: the edge HTTP daemon for the Pixel 8 Pro (GrapheneOS, Termux).

This is the single home of the gateway. Froogle's launch/scripts/pixel_gateway.py was a fork
of this file; the two were merged here (union of features, strictest security) and Froogle now
keeps only a shim that execs this copy.

Routes
  GET  /                      -> "pixel-agent-v2 ok"                         (never needs token)
  GET  /health                -> liveness, auth mode; device readings only if authorized (open)
  GET  /telemetry             -> battery, telephony (real readings only), storage
  GET  /inbound/sms           -> recent inbox via termux-sms-list (alias /sms/inbox)
  POST /inbound/sync          -> push recent inbox to INBOUND_SYNC_URL (sovereign-carrier)
  POST /chat                  -> edge chat / reflex inference
  POST /v1/chat/completions   -> OpenAI-compatible endpoint for swarm dispatch (pixel-8/ models)
  POST /actuate/sms           -> termux-sms-send
  POST /actuate/camera        -> termux-camera-photo
  POST /actuate/torch         -> termux-torch
  POST /actuate/vibrate       -> termux-vibrate

Security contract (phone-side version of the Froogle local-daemon contract)
  1. Bind: BIND_HOST, default 127.0.0.1. The Mac reaches the gateway through
     `adb forward tcp:18790 tcp:18790`, and adbd connects to the PHONE's loopback, so 127.0.0.1
     is all adb needs. The old 0.0.0.0 bind also exposed the gateway (SMS send, inbox read) on
     Wi-Fi / cellular / Tailscale. Set BIND_HOST=0.0.0.0 only on purpose; it prints a warning.
  2. Host header must be 127.0.0.1:<port>, localhost:<port> or [::1]:<port> (plus the bound
     non-wildcard host, plus GATEWAY_ALLOWED_HOSTS). Blocks DNS rebinding.
  3. If an Origin header is present it must be exactly http://<Host> or listed in
     GATEWAY_ALLOWED_ORIGINS. No CORS headers are sent (the old `Access-Control-Allow-Origin: *`
     let any web page in the Mac's browser read the SMS inbox through the adb forward).
  4. POST bodies must be Content-Type application/json and a JSON object (415 / 400), capped
     at GATEWAY_MAX_BODY bytes (413). A text/plain "simple" cross-site POST can no longer fire
     an SMS.
  5. Optional bearer token: GATEWAY_TOKEN, else the file GATEWAY_TOKEN_FILE (default
     ~/.config/pixel-gateway/token, stripped). OFF when neither exists, so the live phone flow
     keeps working. When on, every route except GET / and GET /health needs
     `Authorization: Bearer <token>` (hmac.compare_digest): /telemetry, the inbox reads,
     /inbound/sync, /chat, /v1/chat/completions and every /actuate/* route. /health reports
     "auth": "bearer"|"off" and, with auth on, shows device readings only to a token holder.
     Recommended: any Android app with INTERNET permission can reach the phone's loopback, so
     without a token any installed app can send SMS or read the inbox.
  6. Inputs validated: phone numbers, message length, camera id, camera output path (confined
     to CAMERA_DIRS, .jpg/.jpeg basename, no symlink), vibrate duration, torch flag.
  7. Every subprocess call is an argv list (no shell=True). termux-sms-send gets `--` before
     the message so a message starting with "-" cannot be parsed as an option.
  8. SMS sends are rate limited (SMS_RATE_PER_MIN, default 10, 0 disables).
  9. Never report success for a failed action (torch / vibrate used to ignore the exit code).

Env: PORT, BIND_HOST, REFLEXIVE_URL, GATEWAY_TOKEN, GATEWAY_TOKEN_FILE, GATEWAY_ALLOWED_HOSTS,
     GATEWAY_ALLOWED_ORIGINS, GATEWAY_MAX_BODY, INBOUND_SYNC_URL, CAMERA_DIRS, SMS_MAX_LEN,
     SMS_RATE_PER_MIN, GATEWAY_WAKELOCK (default 1).
"""

import hmac
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

PORT = int(os.environ.get("PORT", "18790"))
BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1").strip() or "127.0.0.1"
REFLEXIVE_URL = os.environ.get("REFLEXIVE_URL", "http://127.0.0.1:9090")
INBOUND_SYNC_URL = os.environ.get("INBOUND_SYNC_URL", "http://127.0.0.1:8795/incoming")
MAX_BODY = int(os.environ.get("GATEWAY_MAX_BODY", str(1024 * 1024)))
SMS_MAX_LEN = int(os.environ.get("SMS_MAX_LEN", "1600"))
SMS_RATE_PER_MIN = int(os.environ.get("SMS_RATE_PER_MIN", "10"))
START_TIME = time.time()

LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")
# Digits with an optional leading +, 3..15 digits (E.164 max is 15; short codes are 3+).
PHONE_RE = re.compile(r"^\+?[0-9]{3,15}$")
PHONE_STRIP_RE = re.compile(r"[\s().-]")
CAMERA_NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}\.(jpg|jpeg)$", re.IGNORECASE)
DEFAULT_CAMERA_PATH = "/sdcard/snapshot.jpg"
VIBRATE_MAX_MS = 5000
PUBLIC_GET_PATHS = ("", "/", "/health")


# ---------------------------------------------------------------------------
# Config helpers (read at call time so tests and operators can change env)
# ---------------------------------------------------------------------------

def _csv_env(name):
    return [p.strip() for p in os.environ.get(name, "").split(",") if p.strip()]


DEFAULT_TOKEN_FILE = "~/.config/pixel-gateway/token"


def gateway_token_file():
    return os.path.expanduser(os.environ.get("GATEWAY_TOKEN_FILE", "").strip() or DEFAULT_TOKEN_FILE)


def gateway_token():
    """The bearer token, or "" when auth is off.

    GATEWAY_TOKEN (env) wins. If it is unset or blank, read GATEWAY_TOKEN_FILE (default
    ~/.config/pixel-gateway/token), stripped. Neither present = auth off (today's behavior).
    Read on every call so rotating the file takes effect without a restart.
    """
    token = os.environ.get("GATEWAY_TOKEN", "").strip()
    if token:
        return token
    try:
        with open(gateway_token_file(), "r", encoding="utf-8") as f:
            return f.read().strip()
    except (OSError, UnicodeDecodeError):
        return ""


def token_matches(header_value, token):
    """Constant-time check of an Authorization header against the token."""
    if not token:
        return False
    auth = header_value or ""
    supplied = auth[7:].strip() if auth.startswith("Bearer ") else ""
    return bool(supplied) and hmac.compare_digest(supplied.encode("utf-8"), token.encode("utf-8"))


def camera_dirs():
    raw = os.environ.get("CAMERA_DIRS", "")
    dirs = [d for d in raw.split(os.pathsep) if d.strip()] if raw else ["/sdcard"]
    return [os.path.realpath(os.path.expanduser(d.strip())) for d in dirs]


def is_loopback(host):
    return host.strip("[]") in LOOPBACK_HOSTS


# ---------------------------------------------------------------------------
# Device helpers (argv lists only, never shell=True)
# ---------------------------------------------------------------------------

def run_cmd(cmd, timeout=10):
    if not isinstance(cmd, (list, tuple)):
        raise TypeError("run_cmd takes an argv list, never a shell string")
    try:
        r = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def get_battery():
    rc, out, _ = run_cmd(["termux-battery-status"], timeout=5)
    if rc == 0 and out:
        try:
            return json.loads(out)
        except Exception:
            pass
    return {"percentage": None, "health": "UNKNOWN", "status": "UNKNOWN", "temperature": None}


def get_telephony():
    """Real readings only: termux-telephony-deviceinfo plus the SIM operator getprops.

    The Froogle fork returned a hardcoded dual-SIM / 5G / IN_SERVICE description regardless of
    what the phone reported; that was removed. Unknown means unknown.
    """
    info = None
    rc, out, _ = run_cmd(["termux-telephony-deviceinfo"], timeout=5)
    if rc == 0 and out:
        try:
            info = json.loads(out)
        except Exception:
            info = None
    _, alpha, _ = run_cmd(["getprop", "gsm.sim.operator.alpha"], timeout=5)
    _, numeric, _ = run_cmd(["getprop", "gsm.sim.operator.numeric"], timeout=5)
    names = [s.strip() for s in alpha.split(",")] if alpha else []
    nums = [s.strip() for s in numeric.split(",")] if numeric else []
    operators = []
    for i in range(max(len(names), len(nums))):
        operators.append({
            "slot_index": i,
            "operator": names[i] if i < len(names) and names[i] else None,
            "numeric": nums[i] if i < len(nums) and nums[i] else None,
        })
    info = info if isinstance(info, dict) else {}
    return {
        "network_type": info.get("data_network_type") or info.get("network_type") or "unknown",
        "sim_state": info.get("sim_state", "unknown"),
        "sim_operators": operators,
        "deviceinfo": info or None,
    }


def get_disk_info():
    try:
        usage = shutil.disk_usage(os.path.expanduser("~"))
        return {
            "total_gb": round(usage.total / (1024**3), 2),
            "used_gb": round(usage.used / (1024**3), 2),
            "free_gb": round(usage.free / (1024**3), 2),
            "free_pct": round(usage.free / usage.total * 100, 1),
        }
    except Exception:
        return {}


def acquire_wakelock():
    """Hold a Termux wakelock so the CPU does not sleep with the screen off."""
    rc, _, _ = run_cmd(["termux-wake-lock"], timeout=5)
    return rc == 0


def get_inbound_sms(limit=10):
    limit = max(1, min(int(limit), 100))
    rc, out, _ = run_cmd(["termux-sms-list", "-l", str(limit), "-t", "inbox"], timeout=10)
    if rc == 0 and out:
        try:
            data = json.loads(out)
            return data if isinstance(data, list) else []
        except Exception:
            pass
    return []


def query_reflexive_model(prompt):
    """Forward to the on-device reflexive model (REFLEXIVE_URL, port 9090)."""
    try:
        url = f"{REFLEXIVE_URL.rstrip('/')}/v1/chat/completions"
        payload = json.dumps({
            "model": "gemma-2b",
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 512,
        }).encode("utf-8")
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            choices = data.get("choices", [])
            if choices:
                return choices[0].get("message", {}).get("content", "")
    except Exception:
        pass
    return None


def edge_agent_reply(message):
    """Rule-based fallback when the reflexive model is absent."""
    msg_lower = message.lower().strip()
    bat = get_battery()

    if any(k in msg_lower for k in ["battery", "charge", "power"]):
        return (f"Pixel 8 Pro Battery: {bat.get('percentage', '?')}% | Status: {bat.get('status', '?')} | "
                f"Health: {bat.get('health', '?')} | Temp: {bat.get('temperature', '?')}°C")

    if any(k in msg_lower for k in ["telemetry", "status", "health", "system"]):
        disk = get_disk_info()
        uptime = int(time.time() - START_TIME)
        return (f"Pixel 8 Pro (GrapheneOS) Edge Node Online. Uptime: {uptime}s. "
                f"Battery: {bat.get('percentage', '?')}%. Storage free: {disk.get('free_gb', '?')} GB.")

    if any(k in msg_lower for k in ["camera", "snap", "photo"]):
        return "Edge Camera ready. Actuate via POST /actuate/camera with {'camera_id': 0}."

    if any(k in msg_lower for k in ["sms", "text", "cellular"]):
        return "Cellular SMS ready. Actuate via POST /actuate/sms with {'to': '<number>', 'message': '<text>'}."

    return f"pixel-8-alpha edge node acknowledged: '{message[:100]}'. Local hardware responsive."


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class Invalid(ValueError):
    pass


def validate_number(value):
    if not isinstance(value, str):
        raise Invalid("'to' must be a string")
    num = PHONE_STRIP_RE.sub("", value.strip())
    if not PHONE_RE.match(num):
        raise Invalid("'to' must be a phone number: optional +, then 3 to 15 digits")
    return num


def validate_sms_text(value):
    if not isinstance(value, str):
        raise Invalid("'message' must be a string")
    text = value.strip()
    if not text:
        raise Invalid("'message' is required")
    if len(text) > SMS_MAX_LEN:
        raise Invalid(f"'message' longer than {SMS_MAX_LEN} characters")
    if "\x00" in text:
        raise Invalid("'message' contains a NUL byte")
    return text


def validate_camera_id(value):
    if isinstance(value, int) and not isinstance(value, bool):
        cid = value
    elif isinstance(value, str) and re.fullmatch(r"[0-9]", value.strip()):
        cid = int(value.strip())
    else:
        raise Invalid("'camera_id' must be an integer 0-9")
    if not 0 <= cid <= 9:
        raise Invalid("'camera_id' must be an integer 0-9")
    return cid


def validate_camera_path(value):
    if value is None:
        value = DEFAULT_CAMERA_PATH
    if not isinstance(value, str) or not value.strip():
        raise Invalid("'output_path' must be a string")
    path = os.path.expanduser(value.strip())
    if not os.path.isabs(path):
        raise Invalid("'output_path' must be absolute")
    name = os.path.basename(path)
    if not CAMERA_NAME_RE.match(name):
        raise Invalid("'output_path' file name must be [A-Za-z0-9._-] ending .jpg or .jpeg")
    if os.path.islink(path):
        raise Invalid("'output_path' must not be a symlink")
    parent = os.path.realpath(os.path.dirname(path))
    if parent not in camera_dirs():
        raise Invalid("'output_path' must be directly inside one of CAMERA_DIRS")
    return os.path.join(parent, name)


def validate_vibrate_ms(value):
    if isinstance(value, bool):
        raise Invalid("'duration_ms' must be an integer")
    try:
        ms = int(value)
    except (TypeError, ValueError):
        raise Invalid("'duration_ms' must be an integer")
    if isinstance(value, float) and value != ms:
        raise Invalid("'duration_ms' must be an integer")
    if not 1 <= ms <= VIBRATE_MAX_MS:
        raise Invalid(f"'duration_ms' must be 1-{VIBRATE_MAX_MS}")
    return ms


def prompt_from_messages(messages):
    if not isinstance(messages, list):
        raise Invalid("'messages' must be a list")
    if not messages:
        return "ping"
    last = messages[-1]
    if not isinstance(last, dict):
        raise Invalid("'messages' entries must be objects")
    content = last.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):  # OpenAI multi-part content
        return " ".join(p.get("text", "") for p in content
                        if isinstance(p, dict) and isinstance(p.get("text"), str))
    raise Invalid("'content' must be a string or a list of parts")


class RateLimiter:
    """Sliding one-minute window. limit <= 0 disables."""

    def __init__(self, limit, window=60.0, clock=time.monotonic):
        self.limit = limit
        self.window = window
        self.clock = clock
        self.hits = []
        self.lock = threading.Lock()

    def allow(self):
        if self.limit <= 0:
            return True
        with self.lock:
            now = self.clock()
            self.hits = [t for t in self.hits if now - t < self.window]
            if len(self.hits) >= self.limit:
                return False
            self.hits.append(now)
            return True


SMS_LIMITER = RateLimiter(SMS_RATE_PER_MIN)


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

class GatewayHandler(http.server.BaseHTTPRequestHandler):
    server_version = "pixel-agent-v2"
    sys_version = ""

    def _send_json(self, status_code, data):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, status_code, text):
        body = text.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    # -- contract -----------------------------------------------------------

    def _allowed_hosts(self):
        bound, port = self.server.server_address[:2]
        allowed = {f"127.0.0.1:{port}", f"localhost:{port}", f"[::1]:{port}"}
        if bound and not is_loopback(bound) and bound not in ("0.0.0.0", "::"):
            allowed.add(f"{bound}:{port}")
        allowed.update(h.lower() for h in _csv_env("GATEWAY_ALLOWED_HOSTS"))
        return allowed

    def _guard(self, path):
        """Apply the contract. True = proceed; False = an error was already sent."""
        host = (self.headers.get("Host") or "").strip().lower()
        if host not in self._allowed_hosts():
            self._send_json(403, {"status": "error", "error": "forbidden: Host header not allowed"})
            return False
        origin = self.headers.get("Origin")
        if origin is not None:
            o = origin.strip().lower()
            if o != f"http://{host}" and o not in {x.lower() for x in _csv_env("GATEWAY_ALLOWED_ORIGINS")}:
                self._send_json(403, {"status": "error", "error": "forbidden: cross-origin request"})
                return False
        if self.command == "POST":
            ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            if ctype != "application/json":
                self._send_json(415, {"status": "error", "error": "Content-Type must be application/json"})
                return False
        token = gateway_token()
        if token and not (self.command == "GET" and path in PUBLIC_GET_PATHS):
            if not token_matches(self.headers.get("Authorization"), token):
                self._send_json(401, {"status": "error", "error": "unauthorized: missing or invalid bearer token"})
                return False
        return True

    def _read_body(self):
        """Returns (ok, dict). On failure the error has been sent."""
        raw = self.headers.get("Content-Length")
        try:
            length = int(raw) if raw is not None else 0
        except ValueError:
            self._send_json(400, {"status": "error", "error": "invalid Content-Length"})
            return False, None
        if length < 0:
            self._send_json(400, {"status": "error", "error": "invalid Content-Length"})
            return False, None
        if length > MAX_BODY:
            self._send_json(413, {"status": "error", "error": f"body larger than {MAX_BODY} bytes"})
            return False, None
        data = self.rfile.read(length) if length else b""
        if not data.strip():
            return True, {}
        try:
            body = json.loads(data.decode("utf-8"))
        except Exception:
            self._send_json(400, {"status": "error", "error": "invalid json"})
            return False, None
        if not isinstance(body, dict):
            self._send_json(400, {"status": "error", "error": "body must be a JSON object"})
            return False, None
        return True, body

    # -- verbs --------------------------------------------------------------

    def do_OPTIONS(self):
        # No CORS: browsers get no Access-Control-Allow-* headers, so cross-origin preflights fail.
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_PUT(self):
        self._send_json(405, {"status": "error", "error": "method not allowed"})

    do_DELETE = do_PUT
    do_PATCH = do_PUT

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path.rstrip("/")
        if not self._guard(path):
            return
        if path == "":
            return self._send_text(200, "pixel-agent-v2 ok\n")

        if path == "/health":
            # Open route. With auth on, an unauthenticated caller gets liveness + auth mode only;
            # device readings (battery, storage, uptime) need the token like /telemetry does.
            token = gateway_token()
            health = {
                "status": "ok",
                "agent": "pixel-8-alpha",
                "capabilities": ["chat", "telemetry", "camera", "sms", "sms_inbox", "torch", "vibrate"],
                "auth": "bearer" if token else "off",
            }
            if not token or token_matches(self.headers.get("Authorization"), token):
                bat = get_battery()
                health.update({
                    "device": "Pixel 8 Pro",
                    "os": "GrapheneOS (Android ARM64)",
                    "uptime_seconds": int(time.time() - START_TIME),
                    "battery": {k: bat.get(k) for k in ("percentage", "health", "temperature", "status")},
                    "storage": get_disk_info(),
                })
            return self._send_json(200, health)

        if path == "/telemetry":
            return self._send_json(200, {
                "timestamp": time.time(),
                "agent": "pixel-8-alpha",
                "device": "Pixel 8 Pro",
                "uptime_seconds": int(time.time() - START_TIME),
                "battery": get_battery(),
                "telephony": get_telephony(),
                "storage": get_disk_info(),
            })

        if path in ("/inbound/sms", "/sms/inbox"):
            messages = get_inbound_sms(limit=20)
            return self._send_json(200, {"inbox_count": len(messages), "messages": messages})

        return self._send_json(404, {"error": "endpoint not found"})

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path.rstrip("/")
        if not self._guard(path):
            return
        ok, body = self._read_body()
        if not ok:
            return
        try:
            return self._route_post(path, body)
        except Invalid as e:
            return self._send_json(400, {"status": "error", "error": str(e)})

    def _route_post(self, path, body):
        if path == "/inbound/sync":
            target = INBOUND_SYNC_URL
            asked = body.get("target_url")
            # The fork let the caller pick target_url: an open relay for the SMS inbox (2FA
            # codes included). The target is operator config only.
            if asked is not None and asked != target:
                raise Invalid("target_url is fixed by INBOUND_SYNC_URL on the phone")
            synced = 0
            failed = 0
            for m in get_inbound_sms(limit=10):
                if not isinstance(m, dict):
                    continue
                sender = m.get("number") or m.get("address") or m.get("sender") or m.get("from")
                text = m.get("body") or m.get("message")
                if not sender or not text:
                    continue
                try:
                    req = urllib.request.Request(
                        target,
                        data=json.dumps({"From": sender, "Body": text}).encode("utf-8"),
                        headers={"Content-Type": "application/json"},
                    )
                    with urllib.request.urlopen(req, timeout=5) as resp:
                        if resp.status in (200, 201):
                            synced += 1
                        else:
                            failed += 1
                except Exception:
                    failed += 1
            status = "ok" if failed == 0 else ("partial" if synced else "error")
            return self._send_json(200 if failed == 0 else 502,
                                   {"status": status, "synced": synced, "failed": failed, "target": target})

        if path == "/chat":
            msg = body.get("message", "")
            if not isinstance(msg, str) or not msg.strip():
                raise Invalid("missing message")
            msg = msg.strip()
            reply = query_reflexive_model(msg) or edge_agent_reply(msg)
            return self._send_json(200, {"reply": reply})

        if path == "/v1/chat/completions":
            last_prompt = prompt_from_messages(body.get("messages", []))
            reply = query_reflexive_model(last_prompt) or edge_agent_reply(last_prompt)
            model = body.get("model")
            if not isinstance(model, str) or not model or len(model) > 128:
                model = "pixel-8/edge"
            p_tok, c_tok = len(last_prompt.split()), len(reply.split())
            return self._send_json(200, {
                "id": f"chatcmpl-pixel8-{int(time.time())}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": reply},
                    "finish_reason": "stop",
                }],
                "usage": {"prompt_tokens": p_tok, "completion_tokens": c_tok, "total_tokens": p_tok + c_tok},
            })

        if path == "/actuate/sms":
            if not body.get("to") or not body.get("message"):
                raise Invalid("both 'to' and 'message' are required")
            recipient = validate_number(body.get("to"))
            text = validate_sms_text(body.get("message"))
            if not SMS_LIMITER.allow():
                return self._send_json(429, {"status": "error", "error": "sms rate limit exceeded"})
            # `--` ends getopts in termux-sms-send so a message starting with "-" stays text.
            rc, _, stderr = run_cmd(["termux-sms-send", "-n", recipient, "--", text], timeout=15)
            if rc == 0:
                return self._send_json(200, {
                    "status": "sent",
                    "to": recipient,
                    "message_length": len(text),
                    "timestamp": time.time(),
                })
            return self._send_json(500, {"status": "error", "error": stderr or "failed to send sms"})

        if path == "/actuate/camera":
            cid = validate_camera_id(body.get("camera_id", 0))
            out_path = validate_camera_path(body.get("output_path"))
            # Fork fix kept: clear the stale file, then poll, since the capture lands async.
            if os.path.exists(out_path):
                try:
                    os.remove(out_path)
                except Exception:
                    pass
            rc, _, stderr = run_cmd(["termux-camera-photo", "-c", str(cid), out_path], timeout=15)
            size = 0
            for _ in range(30):
                if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
                    size = os.path.getsize(out_path)
                    break
                time.sleep(0.1)
            if size > 0:
                return self._send_json(200, {
                    "status": "captured",
                    "camera_id": str(cid),
                    "output_path": out_path,
                    "bytes": size,
                    "timestamp": time.time(),
                })
            return self._send_json(500, {"status": "error", "error": stderr or "camera capture failed"})

        if path == "/actuate/torch":
            enabled = body.get("enabled", True)
            if not isinstance(enabled, bool):
                raise Invalid("'enabled' must be true or false")
            state = "on" if enabled else "off"
            rc, _, stderr = run_cmd(["termux-torch", state], timeout=5)
            if rc != 0:
                return self._send_json(500, {"status": "error", "error": stderr or "torch failed"})
            return self._send_json(200, {"status": "ok", "torch": state})

        if path == "/actuate/vibrate":
            ms = validate_vibrate_ms(body.get("duration_ms", 300))
            rc, _, stderr = run_cmd(["termux-vibrate", "-d", str(ms)], timeout=5)
            if rc != 0:
                return self._send_json(500, {"status": "error", "error": stderr or "vibrate failed"})
            return self._send_json(200, {"status": "ok", "duration_ms": ms})

        return self._send_json(404, {"error": "endpoint not found"})

    def log_message(self, fmt, *args):
        sys.stderr.write(f"pixel-gateway: {self.address_string()} {fmt % args}\n")
        sys.stderr.flush()


def make_server(host=None, port=None):
    return http.server.ThreadingHTTPServer((host or BIND_HOST, PORT if port is None else port), GatewayHandler)


def main():
    if os.environ.get("GATEWAY_WAKELOCK", "1") != "0":
        acquire_wakelock()
    if not is_loopback(BIND_HOST):
        print(f"WARNING: binding {BIND_HOST}: the gateway (SMS send, inbox read) is reachable off-device. "
              f"adb forward only needs 127.0.0.1.", file=sys.stderr)
    if not gateway_token():
        print(f"note: no GATEWAY_TOKEN and no token file at {gateway_token_file()}; "
              "any local process or app on the phone can call every route.",
              file=sys.stderr)
    httpd = make_server()
    print(f"Pixel Edge Gateway listening on http://{BIND_HOST}:{PORT} (REFLEXIVE_URL={REFLEXIVE_URL})",
          file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down Pixel Edge Gateway...", file=sys.stderr)
        httpd.server_close()


if __name__ == "__main__":
    main()
