# Next on the Plan (Sovereign Mobile Nexus)

What's done vs what's left from the Android 16 edge-server roadmap.

## Done

| Item | Status |
|------|--------|
| ADB + PPK disabled | Done (`scripts/disable-ppk.sh`, `verify-setup.sh`) |
| SSH (8022) + Tailscale | Done (Tailnet 100.78.73.64, USB fallback) |
| Docker in VM | Done |
| OpenClaw + Mission Control (18789) | Done |
| OpenClaw persistent daemon | Done (systemd user service + taskset) |
| Tensor G3 taskset | Done (doc + daemon uses prime core) |
| Thermal check script | Done (cron every 5 min) |
| Wakelock / persistence notes | Done (`optional-setup.md`) |
| **Claude Gateway v1 (AI inference server)** | **Done** (`claude-gateway/`, `scripts/setup-claude-gateway*.sh`) |
| **OpenClaw Heartbeat (AI health monitor)** | **Done** (`scripts/claude-heartbeat.sh`) |
| **Claude Gateway v2** | **Done** — Prometheus metrics, rate limiting, Bearer auth, 4 new agent tools (`read_file`, `write_file`, `restart_service`, `http_fetch`), streaming agent SSE endpoint (`/v1/agent/stream`), local LLM routing |
| **llama.cpp SVE build automation** | **Done** (`scripts/setup-llama-sve.sh`) — ARM SVE optimized, systemd service, auto-links to Claude Gateway |
| **Homelab Docker stack** | **Done** (`homelab/docker-compose.yml`, `scripts/setup-homelab.sh`) — Ollama + Jellyfin + NGINX reverse proxy |

---

## Next (in priority order)

### 1. VNC desktop in the VM (optional)

Run a Linux desktop in the VM and view it via VNC on the phone or from your Mac.

- **Install:** `apt install tigervnc-standalone-server xfce4 dbus-x11`, then `vncserver :1`
- **Port:** 5901. Connect from Mac with any VNC client to `100.78.73.64:5901`
- **Note:** Pixel 8 Pro uses lavapipe (software GPU) in the VM; no hardware acceleration

See `scripts/setup-vnc-in-vm.sh` (run from Mac) to automate install.

---

### 2. Local LLM — use it

Now that `scripts/setup-llama-sve.sh` is available:

```bash
# Build llama.cpp with SVE, download Llama-3.2-3B, link to Claude Gateway
bash scripts/setup-llama-sve.sh

# Or run Ollama via homelab stack
bash scripts/setup-homelab.sh
```

With `LOCAL_LLM_URL` set in the gateway env, requesting model `"local"` or any `haiku/*`
model name routes to your on-device LLM instead of the Claude API — zero API cost.

See `docs/local-llm-in-vm.md` for detail on both backends.

---

### 3. Hybrid NPU inference (VM + Android host)

Use the Tensor G3 NPU on the Android host while the agent runs in the VM.

- **Android host:** Install an app that runs MediaPipe LLM Inference and accepts prompts
  (local API or `adb shell`)
- **VM bridge:** `adb connect 127.0.0.1:5555`, then call the host-side inference API

See `scripts/npu-bridge.sh` (stub, needs host-side implementation) and
`docs/hybrid-npu-inference.md`.

---

### 4. Prometheus + Grafana monitoring (optional)

Claude Gateway v2 exposes `/metrics` in Prometheus format.

```bash
# Quick local scrape
curl http://100.78.73.64:3456/metrics

# Add to Prometheus scrape_configs
- job_name: pixel_gateway
  static_configs:
    - targets: ['100.78.73.64:3456']
```

Grafana is **not** in `homelab/docker-compose.yml` by default (memory headroom on 12 GB RAM). To add it, append to the compose file:

```yaml
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
```

And add `grafana_data:` under the top-level `volumes:` key. Then add Prometheus as a data source pointing at `http://100.78.73.64:3456/metrics`.

---

### 5. 16KB memory pages (optional, destructive)

Can improve memory efficiency for VM workloads.

- **Cost:** Bootloader unlock + factory reset — not reversible without reflashing
- **Skip by default.** Only do this if you need maximum VM memory performance

---

## Quick Reference: What to run next

| Goal | Command |
|------|---------|
| Enable on-device LLM (llama.cpp, SVE-optimized) | `bash scripts/setup-llama-sve.sh` |
| Start full homelab (Ollama + Jellyfin + NGINX) | `bash scripts/setup-homelab.sh` |
| Enable VNC desktop | `bash scripts/setup-vnc-in-vm.sh` |
| Prometheus metrics | `curl http://100.78.73.64:3456/metrics` |
| Stream a live agent task | `curl -s -XPOST .../v1/agent/stream ...` |
