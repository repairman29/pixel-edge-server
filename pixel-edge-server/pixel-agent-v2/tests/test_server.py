"""Tests for pixel-agent-v2/server.py, run on the Mac. Every Termux / Android call is mocked:
run_cmd is replaced with a recorder, so nothing touches a phone and no SMS is sent.

Depth: happy-path for every route, plus edge and adversarial cases for the security contract
(Host, Origin, Content-Type, body shape and size, bearer token), input validation (numbers,
option injection, camera path confinement, vibrate bounds), rate limiting, and the
no-false-success rule. Gaps: nothing runs against real termux-* binaries or a real device;
the `--` handling in termux-sms-send is asserted on argv only, not on the device.
"""

import http.client
import importlib.util
import json
import os
import threading
from pathlib import Path

import pytest

SERVER_PATH = Path(__file__).resolve().parent.parent / "server.py"


def load_module():
    spec = importlib.util.spec_from_file_location("pixel_gateway_server", SERVER_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FakeCmds:
    def __init__(self):
        self.calls = []
        self.results = {}

    def __call__(self, cmd, timeout=10):
        assert isinstance(cmd, (list, tuple)), "run_cmd must get an argv list"
        self.calls.append(list(cmd))
        return self.results.get(cmd[0], (0, "", ""))


@pytest.fixture
def gw(monkeypatch, tmp_path):
    for var in ("GATEWAY_TOKEN", "GATEWAY_ALLOWED_HOSTS", "GATEWAY_ALLOWED_ORIGINS", "CAMERA_DIRS"):
        monkeypatch.delenv(var, raising=False)
    # Never pick up a real token file from the operator's home directory.
    monkeypatch.setenv("GATEWAY_TOKEN_FILE", str(tmp_path / "no-such-token"))
    mod = load_module()
    fake = FakeCmds()
    monkeypatch.setattr(mod, "run_cmd", fake)
    monkeypatch.setattr(mod, "query_reflexive_model", lambda prompt: None)
    monkeypatch.setattr(mod.time, "sleep", lambda s: None)
    monkeypatch.setenv("CAMERA_DIRS", str(tmp_path))
    mod.SMS_LIMITER = mod.RateLimiter(100)
    httpd = mod.make_server("127.0.0.1", 0)
    t = threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
    t.start()
    port = httpd.server_address[1]

    class Client:
        pass

    c = Client()
    c.mod, c.fake, c.port, c.tmp = mod, fake, port, tmp_path

    def request(method, path, body=None, headers=None, raw=None):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        h = {"Host": f"127.0.0.1:{port}"}
        data = raw
        if body is not None:
            data = json.dumps(body).encode()
            h["Content-Type"] = "application/json"
        h.update(headers or {})
        conn.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
        for k, v in h.items():
            conn.putheader(k, v)
        if data is not None:
            conn.putheader("Content-Length", str(len(data)))
        conn.endheaders()
        if data is not None:
            conn.send(data)
        resp = conn.getresponse()
        payload = resp.read()
        conn.close()
        try:
            parsed = json.loads(payload)
        except Exception:
            parsed = payload.decode()
        return resp.status, parsed, dict(resp.getheaders())

    c.req = request
    yield c
    httpd.shutdown()
    httpd.server_close()


def sms_calls(fake):
    return [c for c in fake.calls if c[0] == "termux-sms-send"]


# --- routes: happy path ------------------------------------------------------

def test_root_and_health(gw):
    s, body, headers = gw.req("GET", "/")
    assert s == 200 and body == "pixel-agent-v2 ok\n"
    assert "Access-Control-Allow-Origin" not in headers
    s, body, _ = gw.req("GET", "/health")
    assert s == 200 and body["status"] == "ok" and body["auth"] == "off"


def test_telemetry_reports_real_readings_not_hardcoded(gw):
    gw.fake.results["termux-telephony-deviceinfo"] = (0, json.dumps({"data_network_type": "lte", "sim_state": "ready"}), "")
    gw.fake.results["getprop"] = (0, "CarrierA,CarrierB", "")
    s, body, _ = gw.req("GET", "/telemetry")
    tel = body["telephony"]
    assert s == 200 and tel["network_type"] == "lte" and tel["sim_state"] == "ready"
    assert [o["operator"] for o in tel["sim_operators"]] == ["CarrierA", "CarrierB"]
    assert "slots" not in tel  # the fork's fabricated dual-SIM block is gone


def test_telemetry_unknown_when_termux_fails(gw):
    gw.fake.results["termux-telephony-deviceinfo"] = (1, "", "no api")
    gw.fake.results["getprop"] = (1, "", "")
    s, body, _ = gw.req("GET", "/telemetry")
    assert body["telephony"]["network_type"] == "unknown"
    assert body["telephony"]["sim_operators"] == []


def test_inbox_routes(gw):
    gw.fake.results["termux-sms-list"] = (0, json.dumps([{"number": "+15550001111", "body": "hi"}]), "")
    for path in ("/inbound/sms", "/sms/inbox"):
        s, body, _ = gw.req("GET", path)
        assert s == 200 and body["inbox_count"] == 1


def test_chat_and_completions(gw):
    s, body, _ = gw.req("POST", "/chat", {"message": "battery?"})
    assert s == 200 and "Battery" in body["reply"]
    s, body, _ = gw.req("POST", "/v1/chat/completions",
                        {"model": "pixel-8/edge", "messages": [{"role": "user", "content": "hello"}]})
    assert s == 200 and body["object"] == "chat.completion" and body["model"] == "pixel-8/edge"
    s, body, _ = gw.req("POST", "/v1/chat/completions",
                        {"messages": [{"role": "user", "content": [{"type": "text", "text": "status"}]}]})
    assert s == 200 and "Edge Node Online" in body["choices"][0]["message"]["content"]


def test_completions_rejects_bad_shapes(gw):
    for bad in ({"messages": "x"}, {"messages": ["x"]}, {"messages": [{"content": 5}]}):
        s, _, _ = gw.req("POST", "/v1/chat/completions", bad)
        assert s == 400
    s, _, _ = gw.req("POST", "/chat", {"message": 5})
    assert s == 400


def test_sms_send_argv(gw):
    s, body, _ = gw.req("POST", "/actuate/sms", {"to": "+1 (555) 000-1111", "message": "hello"})
    assert s == 200 and body["status"] == "sent" and body["to"] == "+15550001111"
    assert sms_calls(gw.fake)[-1] == ["termux-sms-send", "-n", "+15550001111", "--", "hello"]


def test_sms_failure_is_not_success(gw):
    gw.fake.results["termux-sms-send"] = (1, "", "boom")
    s, body, _ = gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"})
    assert s == 500 and body["status"] == "error"


# --- input validation / injection ---------------------------------------------

@pytest.mark.parametrize("to", [
    "-s", "--es foo bar", "+1555,+1666", "5550001111 extra", "abc", "12", "+1234567890123456",
    "$(reboot)", "5550001111;id", "", 5550001111, None,
])
def test_sms_rejects_bad_numbers(gw, to):
    s, _, _ = gw.req("POST", "/actuate/sms", {"to": to, "message": "hi"})
    assert s == 400
    assert sms_calls(gw.fake) == []


def test_sms_message_starting_with_dash_stays_text(gw):
    s, _, _ = gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "-s 1 hi"})
    assert s == 200
    argv = sms_calls(gw.fake)[-1]
    assert argv[argv.index("--") + 1] == "-s 1 hi"


def test_sms_message_limits(gw):
    s, _, _ = gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x" * 1601})
    assert s == 400
    s, _, _ = gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": ["x"]})
    assert s == 400
    assert sms_calls(gw.fake) == []


def test_sms_rate_limit(gw):
    gw.mod.SMS_LIMITER = gw.mod.RateLimiter(2)
    codes = [gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"})[0] for _ in range(3)]
    assert codes == [200, 200, 429]
    assert len(sms_calls(gw.fake)) == 2


def test_camera_happy_path(gw):
    out = gw.tmp / "snap.jpg"

    def fake_cmd(cmd, timeout=10):
        gw.fake.calls.append(list(cmd))
        if cmd[0] == "termux-camera-photo":
            Path(cmd[-1]).write_bytes(b"jpegdata")
        return 0, "", ""

    gw.mod.run_cmd = fake_cmd
    out.write_bytes(b"stale")
    s, body, _ = gw.req("POST", "/actuate/camera", {"camera_id": 1, "output_path": str(out)})
    assert s == 200 and body["bytes"] == len(b"jpegdata")
    assert gw.fake.calls[-1] == ["termux-camera-photo", "-c", "1", str(out.resolve())]


def test_camera_failure_when_no_file(gw):
    s, body, _ = gw.req("POST", "/actuate/camera", {"camera_id": 0, "output_path": str(gw.tmp / "a.jpg")})
    assert s == 500 and body["status"] == "error"


@pytest.mark.parametrize("path", [
    "/etc/passwd", "/data/data/com.termux/files/home/.bashrc", "relative.jpg", "../x.jpg",
    "{tmp}/../escape.jpg", "{tmp}/sub/x.jpg", "{tmp}/x.png", "{tmp}/-c.jpg x", 5,
])
def test_camera_path_confinement(gw, path):
    if isinstance(path, str):
        path = path.replace("{tmp}", str(gw.tmp))
    s, _, _ = gw.req("POST", "/actuate/camera", {"camera_id": 0, "output_path": path})
    assert s == 400
    assert not [c for c in gw.fake.calls if c[0] == "termux-camera-photo"]


def test_camera_symlink_refused(gw, tmp_path_factory):
    victim = tmp_path_factory.mktemp("victim") / "keep.jpg"
    victim.write_bytes(b"keep")
    link = gw.tmp / "link.jpg"
    os.symlink(victim, link)
    s, _, _ = gw.req("POST", "/actuate/camera", {"camera_id": 0, "output_path": str(link)})
    assert s == 400 and victim.read_bytes() == b"keep"


@pytest.mark.parametrize("cid", ["-1", 10, "0; id", True, 1.5, "--help"])
def test_camera_id_validation(gw, cid):
    s, _, _ = gw.req("POST", "/actuate/camera", {"camera_id": cid, "output_path": str(gw.tmp / "a.jpg")})
    assert s == 400


def test_torch_and_vibrate(gw):
    s, body, _ = gw.req("POST", "/actuate/torch", {"enabled": False})
    assert s == 200 and body["torch"] == "off"
    s, body, _ = gw.req("POST", "/actuate/vibrate", {"duration_ms": 250})
    assert s == 200 and gw.fake.calls[-1] == ["termux-vibrate", "-d", "250"]
    # portal forwards its whole body including "action"; extra keys are ignored
    s, _, _ = gw.req("POST", "/actuate/vibrate", {"action": "vibrate"})
    assert s == 200


@pytest.mark.parametrize("ms", ["abc", -5, 0, 999999, True, 1.5, "-d"])
def test_vibrate_validation(gw, ms):
    s, _, _ = gw.req("POST", "/actuate/vibrate", {"duration_ms": ms})
    assert s == 400


def test_torch_vibrate_failures_not_reported_ok(gw):
    gw.fake.results["termux-torch"] = (1, "", "no torch")
    gw.fake.results["termux-vibrate"] = (1, "", "no vib")
    assert gw.req("POST", "/actuate/torch", {"enabled": True})[0] == 500
    assert gw.req("POST", "/actuate/vibrate", {"duration_ms": 100})[0] == 500
    assert gw.req("POST", "/actuate/torch", {"enabled": "yes"})[0] == 400


# --- inbound sync -------------------------------------------------------------

def test_inbound_sync_refuses_caller_target(gw):
    s, body, _ = gw.req("POST", "/inbound/sync", {"target_url": "http://evil.example/steal"})
    assert s == 400
    assert not [c for c in gw.fake.calls if c[0] == "termux-sms-list"]


def test_inbound_sync_posts_to_configured_target(gw, monkeypatch):
    gw.fake.results["termux-sms-list"] = (0, json.dumps([{"number": "+1555", "body": "a"}, {"x": 1}]), "")
    seen = []

    class Resp:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def fake_urlopen(req, timeout=0):
        seen.append(req.full_url)
        return Resp()

    monkeypatch.setattr(gw.mod.urllib.request, "urlopen", fake_urlopen)
    s, body, _ = gw.req("POST", "/inbound/sync", {})
    assert s == 200 and body["synced"] == 1 and seen == [gw.mod.INBOUND_SYNC_URL]


# --- HTTP contract -------------------------------------------------------------

def test_bad_host_refused(gw):
    for host in ("evil.example", f"evil.example:{gw.port}", "127.0.0.1:1", ""):
        s, _, _ = gw.req("GET", "/telemetry", headers={"Host": host})
        assert s == 403


def test_extra_allowed_host(gw, monkeypatch):
    monkeypatch.setenv("GATEWAY_ALLOWED_HOSTS", "pixel.local:18790")
    assert gw.req("GET", "/health", headers={"Host": "pixel.local:18790"})[0] == 200


def test_origin_must_match(gw):
    s, _, _ = gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"},
                     headers={"Origin": "http://evil.example"})
    assert s == 403 and sms_calls(gw.fake) == []
    s, _, _ = gw.req("GET", "/inbound/sms", headers={"Origin": "null"})
    assert s == 403
    s, _, _ = gw.req("GET", "/health", headers={"Origin": f"http://127.0.0.1:{gw.port}"})
    assert s == 200


def test_post_requires_json_content_type(gw):
    raw = json.dumps({"to": "5550001111", "message": "x"}).encode()
    s, _, _ = gw.req("POST", "/actuate/sms", raw=raw, headers={"Content-Type": "text/plain"})
    assert s == 415
    s, _, _ = gw.req("POST", "/actuate/sms", raw=raw)
    assert s == 415
    assert sms_calls(gw.fake) == []


def test_body_shape_and_size(gw):
    j = {"Content-Type": "application/json"}
    assert gw.req("POST", "/chat", raw=b"[1,2]", headers=j)[0] == 400
    assert gw.req("POST", "/chat", raw=b"{nope", headers=j)[0] == 400
    gw.mod.MAX_BODY = 10
    assert gw.req("POST", "/chat", raw=b'{"message": "hello there"}', headers=j)[0] == 413


def test_options_sends_no_cors(gw):
    s, _, headers = gw.req("OPTIONS", "/actuate/sms", headers={"Origin": "http://evil.example"})
    assert not any(k.lower().startswith("access-control") for k in headers)


def test_token_off_by_default_on_when_set(gw, monkeypatch):
    assert gw.req("GET", "/telemetry")[0] == 200
    monkeypatch.setenv("GATEWAY_TOKEN", "s3cret")
    assert gw.req("GET", "/health")[0] == 200
    assert gw.req("GET", "/")[0] == 200
    assert gw.req("GET", "/telemetry")[0] == 401
    assert gw.req("GET", "/inbound/sms")[0] == 401
    assert gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"},
                  headers={"Authorization": "Bearer wrong"})[0] == 401
    assert sms_calls(gw.fake) == []
    assert gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"},
                  headers={"Authorization": "Bearer s3cret"})[0] == 200


def test_run_cmd_refuses_shell_strings():
    mod = load_module()
    with pytest.raises(TypeError):
        mod.run_cmd("termux-sms-send -n 1 hi")


def test_no_shell_true_in_source():
    import ast
    tree = ast.parse(SERVER_PATH.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            assert not any(k.arg == "shell" for k in node.keywords), "subprocess shell= used"
            f = node.func
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "os":
                assert f.attr not in ("system", "popen"), f"os.{f.attr} used"


def test_default_bind_is_loopback(monkeypatch):
    monkeypatch.delenv("BIND_HOST", raising=False)
    assert load_module().BIND_HOST == "127.0.0.1"


# --- token file -----------------------------------------------------------------

AUTH_ROUTES = [
    ("GET", "/telemetry", None),
    ("GET", "/inbound/sms", None),
    ("GET", "/sms/inbox", None),
    ("POST", "/inbound/sync", {}),
    ("POST", "/chat", {"message": "hi"}),
    ("POST", "/v1/chat/completions", {"messages": [{"role": "user", "content": "hi"}]}),
    ("POST", "/actuate/sms", {"to": "5550001111", "message": "x"}),
    ("POST", "/actuate/camera", {"camera_id": 0}),
    ("POST", "/actuate/torch", {"enabled": True}),
    ("POST", "/actuate/vibrate", {"duration_ms": 100}),
]


@pytest.fixture
def token_file(gw, monkeypatch):
    path = gw.tmp / "token"
    path.write_text("  file-s3cret\n")
    monkeypatch.setenv("GATEWAY_TOKEN_FILE", str(path))
    monkeypatch.setattr(gw.mod, "INBOUND_SYNC_URL", "http://127.0.0.1:9/incoming")
    return path


@pytest.mark.parametrize("method,path,body", AUTH_ROUTES)
def test_token_file_requires_bearer_on_every_sensitive_route(gw, token_file, method, path, body):
    assert gw.req(method, path, body)[0] == 401
    assert gw.req(method, path, body, headers={"Authorization": "Bearer wrong"})[0] == 401
    assert gw.req(method, path, body, headers={"Authorization": "file-s3cret"})[0] == 401  # no scheme
    assert gw.fake.calls == []  # nothing reached a termux binary
    s, _, _ = gw.req(method, path, body, headers={"Authorization": "Bearer file-s3cret"})
    assert s != 401


def test_token_file_right_token_sends_sms(gw, token_file):
    s, body, _ = gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"},
                        headers={"Authorization": "Bearer file-s3cret"})
    assert s == 200 and body["status"] == "sent"
    assert len(sms_calls(gw.fake)) == 1


def test_env_token_wins_over_file(gw, token_file, monkeypatch):
    monkeypatch.setenv("GATEWAY_TOKEN", "env-token")
    assert gw.req("GET", "/telemetry", headers={"Authorization": "Bearer file-s3cret"})[0] == 401
    assert gw.req("GET", "/telemetry", headers={"Authorization": "Bearer env-token"})[0] == 200


def test_empty_token_file_keeps_auth_off(gw, monkeypatch):
    path = gw.tmp / "token"
    path.write_text("  \n")
    monkeypatch.setenv("GATEWAY_TOKEN_FILE", str(path))
    assert gw.req("GET", "/telemetry")[0] == 200
    assert gw.req("GET", "/health")[1]["auth"] == "off"


def test_no_token_anywhere_keeps_current_behavior(gw):
    assert gw.mod.gateway_token() == ""
    assert gw.req("GET", "/telemetry")[0] == 200
    assert gw.req("POST", "/actuate/sms", {"to": "5550001111", "message": "x"})[0] == 200
    s, body, _ = gw.req("GET", "/health")
    assert s == 200 and body["auth"] == "off" and "battery" in body and "storage" in body


def test_health_reports_auth_and_hides_readings_without_token(gw, token_file):
    s, body, _ = gw.req("GET", "/health")
    assert s == 200 and body["status"] == "ok" and body["auth"] == "bearer"
    for leaked in ("battery", "storage", "uptime_seconds", "device", "os"):
        assert leaked not in body
    assert "file-s3cret" not in json.dumps(body)
    assert gw.fake.calls == []  # no termux-battery-status call for an anonymous probe
    s, body, _ = gw.req("GET", "/health", headers={"Authorization": "Bearer wrong"})
    assert s == 200 and "battery" not in body
    s, body, _ = gw.req("GET", "/health", headers={"Authorization": "Bearer file-s3cret"})
    assert s == 200 and body["auth"] == "bearer" and "battery" in body and "storage" in body
    assert gw.req("GET", "/")[0] == 200


def test_token_file_rotation_takes_effect_without_restart(gw, token_file):
    assert gw.req("GET", "/telemetry", headers={"Authorization": "Bearer file-s3cret"})[0] == 200
    token_file.write_text("rotated")
    assert gw.req("GET", "/telemetry", headers={"Authorization": "Bearer file-s3cret"})[0] == 401
    assert gw.req("GET", "/telemetry", headers={"Authorization": "Bearer rotated"})[0] == 200


def test_default_token_file_path(monkeypatch):
    monkeypatch.delenv("GATEWAY_TOKEN_FILE", raising=False)
    assert load_module().gateway_token_file() == os.path.expanduser("~/.config/pixel-gateway/token")


def test_token_compare_uses_hmac_compare_digest():
    src = SERVER_PATH.read_text()
    assert "hmac.compare_digest" in src
    mod = load_module()
    assert mod.token_matches("Bearer abc", "abc") is True
    assert mod.token_matches("Bearer abd", "abc") is False
    assert mod.token_matches("Bearer abc", "") is False
    assert mod.token_matches(None, "abc") is False
