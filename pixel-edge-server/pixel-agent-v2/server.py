#!/usr/bin/env python3
"""pixel_gateway.py — High-performance Edge Gateway Daemon for Google Pixel 8 Pro on GrapheneOS.

Listens on 0.0.0.0:18790 (native Termux port allocation).
Provides:
  - GET  /                     -> "pixel-agent-v2 ok"
  - GET  /health               -> Health, battery, hardware, and service status
  - GET  /telemetry            -> Live hardware metrics (battery, 5G cellular, memory, disk)
  - POST /chat                 -> Edge chat / reflex inference endpoint
  - POST /v1/chat/completions  -> OpenAI-compatible endpoint for swarm dispatch
  - POST /actuate/sms          -> Cellular SMS actuator via termux-sms-send
  - POST /actuate/camera       -> Physical camera snapshot actuator via termux-camera-photo
  - POST /actuate/torch        -> Flashlight actuator via termux-torch
  - POST /actuate/vibrate      -> Haptic actuator via termux-vibrate
"""

import http.server
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

PORT = int(os.environ.get("PORT", "18790"))
REFLEXIVE_URL = os.environ.get("REFLEXIVE_URL", "http://127.0.0.1:9090")
START_TIME = time.time()


def run_cmd(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
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
    return {"percentage": 100, "health": "UNKNOWN", "status": "UNKNOWN", "temperature": 25.0}


def get_telephony():
    rc, out, _ = run_cmd(["termux-telephony-deviceinfo"], timeout=5)
    if rc == 0 and out:
        try:
            return json.loads(out)
        except Exception:
            pass
    return {"network_type": "unknown", "sim_state": "unknown"}


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


def query_reflexive_model(prompt):
    """Attempt forwarding to on-device reflexive model on port 9090."""
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
    """Edge reasoning engine when reflexive model is absent or for hardware queries."""
    msg_lower = message.lower().strip()
    bat = get_battery()
    
    if any(k in msg_lower for k in ["battery", "charge", "power"]):
        pct = bat.get("percentage", "?")
        temp = bat.get("temperature", "?")
        status = bat.get("status", "?")
        health = bat.get("health", "?")
        return f"Pixel 8 Pro Battery: {pct}% | Status: {status} | Health: {health} | Temp: {temp}°C"

    if any(k in msg_lower for k in ["telemetry", "status", "health", "system"]):
        disk = get_disk_info()
        uptime = int(time.time() - START_TIME)
        return (f"Pixel 8 Pro (GrapheneOS) Edge Node Online. Uptime: {uptime}s. "
                f"Battery: {bat.get('percentage', '?')}%. Storage free: {disk.get('free_gb', '?')} GB. "
                f"Sensors: Camera (rear 50MP/front 8MP), 5G NR Telephony, SMS actuator active.")

    if any(k in msg_lower for k in ["camera", "snap", "photo"]):
        return "Edge Camera ready. Actuate via POST /actuate/camera with {'camera_id': 0}."

    if any(k in msg_lower for k in ["sms", "text", "cellular"]):
        return "Cellular SMS ready. Actuate via POST /actuate/sms with {'to': '<number>', 'message': '<text>'}."

    # General reflex answer
    return f"pixel-8-alpha edge node acknowledged: '{message[:100]}'. Local hardware responsive."


class GatewayHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, status_code, data):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, status_code, text, content_type="text/plain; charset=utf-8"):
        body = text.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        if path in ("", "/"):
            return self._send_text(200, "pixel-agent-v2 ok\n")

        if path == "/health":
            bat = get_battery()
            disk = get_disk_info()
            return self._send_json(200, {
                "status": "ok",
                "agent": "pixel-8-alpha",
                "device": "Pixel 8 Pro",
                "os": "GrapheneOS (Android 14/15 ARM64)",
                "uptime_seconds": int(time.time() - START_TIME),
                "battery": {
                    "percentage": bat.get("percentage"),
                    "health": bat.get("health"),
                    "temperature": bat.get("temperature"),
                    "status": bat.get("status"),
                },
                "storage": disk,
                "capabilities": ["chat", "telemetry", "camera", "sms", "torch", "vibrate"],
            })

        if path == "/telemetry":
            bat = get_battery()
            tel = get_telephony()
            disk = get_disk_info()
            return self._send_json(200, {
                "timestamp": time.time(),
                "agent": "pixel-8-alpha",
                "device": "Pixel 8 Pro",
                "uptime_seconds": int(time.time() - START_TIME),
                "battery": bat,
                "telephony": tel,
                "storage": disk,
            })

        return self._send_json(404, {"error": "endpoint not found"})

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/")
        content_len = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_len) if content_len > 0 else b"{}"

        try:
            body = json.loads(post_data.decode("utf-8")) if post_data else {}
        except Exception:
            return self._send_json(400, {"error": "invalid json"})

        # 1. /chat endpoint
        if path == "/chat":
            msg = body.get("message", "").strip()
            if not msg:
                return self._send_json(400, {"error": "missing message"})
            reply = query_reflexive_model(msg)
            if not reply:
                reply = edge_agent_reply(msg)
            return self._send_json(200, {"reply": reply})

        # 2. OpenAI-compatible /v1/chat/completions
        if path == "/v1/chat/completions":
            messages = body.get("messages", [])
            last_prompt = messages[-1].get("content", "") if messages else "ping"
            reply = query_reflexive_model(last_prompt)
            if not reply:
                reply = edge_agent_reply(last_prompt)

            return self._send_json(200, {
                "id": f"chatcmpl-pixel8-{int(time.time())}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": body.get("model", "pixel-8/edge"),
                "choices": [{
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": reply,
                    },
                    "finish_reason": "stop",
                }],
                "usage": {
                    "prompt_tokens": len(last_prompt.split()),
                    "completion_tokens": len(reply.split()),
                    "total_tokens": len(last_prompt.split()) + len(reply.split()),
                },
            })

        # 3. /actuate/sms
        if path == "/actuate/sms":
            recipient = body.get("to", "").strip()
            text = body.get("message", "").strip()
            if not recipient or not text:
                return self._send_json(400, {"error": "both 'to' and 'message' are required"})

            rc, stdout, stderr = run_cmd(["termux-sms-send", "-n", recipient, text], timeout=15)
            if rc == 0:
                return self._send_json(200, {
                    "status": "sent",
                    "to": recipient,
                    "message_length": len(text),
                    "timestamp": time.time(),
                })
            else:
                return self._send_json(500, {"status": "error", "error": stderr or "failed to send sms"})

        # 4. /actuate/camera
        if path == "/actuate/camera":
            cid = str(body.get("camera_id", "0"))
            out_path = body.get("output_path", "/sdcard/snapshot.jpg")
            rc, stdout, stderr = run_cmd(["termux-camera-photo", "-c", cid, out_path], timeout=15)
            if rc == 0 and os.path.exists(out_path):
                size = os.path.getsize(out_path)
                return self._send_json(200, {
                    "status": "captured",
                    "camera_id": cid,
                    "output_path": out_path,
                    "bytes": size,
                    "timestamp": time.time(),
                })
            else:
                return self._send_json(500, {"status": "error", "error": stderr or "camera capture failed"})

        # 5. /actuate/torch
        if path == "/actuate/torch":
            state = "on" if body.get("enabled", True) else "off"
            rc, stdout, stderr = run_cmd(["termux-torch", state], timeout=5)
            return self._send_json(200, {"status": "ok", "torch": state})

        # 6. /actuate/vibrate
        if path == "/actuate/vibrate":
            ms = str(body.get("duration_ms", 300))
            rc, stdout, stderr = run_cmd(["termux-vibrate", "-d", ms], timeout=5)
            return self._send_json(200, {"status": "ok", "duration_ms": int(ms)})

        return self._send_json(404, {"error": "endpoint not found"})

    def log_message(self, fmt, *args):
        sys.stderr.write(f"pixel-gateway: {self.address_string()} {fmt % args}\n")
        sys.stderr.flush()


def main():
    server_address = ("0.0.0.0", PORT)
    httpd = http.server.ThreadingHTTPServer(server_address, GatewayHandler)
    print(f"Pixel Edge Gateway listening on http://0.0.0.0:{PORT} (REFLEXIVE_URL={REFLEXIVE_URL})", file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down Pixel Edge Gateway...", file=sys.stderr)
        httpd.server_close()


if __name__ == "__main__":
    main()
