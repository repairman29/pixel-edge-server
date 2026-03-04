#!/usr/bin/env python3
"""Minimal HTTP server: GET /restart-gateway?token=XXX restarts openclaw-gateway. For iPhone Shortcut / Tailscale."""
import os
import subprocess
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("JARVIS_WAKE_PORT", "9180"))
_token_file = os.path.expanduser("~/.openclaw/wake-token")
TOKEN = (os.environ.get("JARVIS_WAKE_TOKEN") or "").strip() or (
    open(_token_file).read().strip() if os.path.isfile(_token_file) else ""
)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        req_token = (query.get("token") or [""])[0]

        if path == "/restart-gateway" or path == "/":
            if TOKEN and req_token != TOKEN:
                self.send_response(403)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Invalid token\n")
                return
            try:
                subprocess.run(
                    ["systemctl", "--user", "restart", "openclaw-gateway.service"],
                    check=True,
                    timeout=10,
                    env={**os.environ, "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")},
                )
                body = b"OK gateway restarting\n"
            except Exception as e:
                body = f"Error: {e}\n".encode()
                self.send_response(500)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/health":
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass  # quiet


if __name__ == "__main__":
    if not TOKEN:
        print("Warning: JARVIS_WAKE_TOKEN unset and no ~/.openclaw/wake-token; /restart-gateway will accept any request.", file=__import__("sys").stderr)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
