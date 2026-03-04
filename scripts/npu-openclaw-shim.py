#!/usr/bin/env python3
"""
OpenClaw shim: exposes NPU bridge as an OpenAI-compatible /v1/chat/completions endpoint.
Run in the Pixel VM. OpenClaw points agents.defaults.model to this (baseUrl http://127.0.0.1:9190).
"""
import json
import os
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("NPU_SHIM_PORT", "9190"))
BRIDGE = os.path.expanduser(os.environ.get("NPU_BRIDGE", "~/bin/npu-bridge.sh"))


def run_bridge(prompt: str) -> str:
    try:
        out = subprocess.run(
            [BRIDGE, prompt],
            capture_output=True,
            text=True,
            timeout=120,
            env={**os.environ},
        )
        if out.returncode != 0:
            return (out.stderr or "unknown error").strip() or "NPU bridge failed"
        return (out.stdout or "").strip()
    except subprocess.TimeoutExpired:
        return "NPU bridge timeout"
    except Exception as e:
        return str(e)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/chat/completions" and self.path != "/v1/chat/completions/":
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get("content-length", 0))
            body = self.rfile.read(length).decode("utf-8")
            data = json.loads(body)
        except Exception as e:
            self.send_response(400)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())
            return
        messages = data.get("messages") or []
        prompt = ""
        for m in reversed(messages):
            if m.get("role") == "user":
                prompt = m.get("content") or ""
                if isinstance(prompt, list):
                    for p in prompt:
                        if isinstance(p, dict) and p.get("type") == "text":
                            prompt = p.get("text", "")
                            break
                break
        if not prompt:
            prompt = "Hello."
        text = run_bridge(prompt)
        # OpenAI-style response
        out = {
            "id": "npu-bridge",
            "object": "chat.completion",
            "choices": [
                {"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        }
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(out).encode())

    def do_GET(self):
        if self.path in ("/health", "/v1/models"):
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"object":"list","data":[{"id":"pixel-npu"}]}')
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
