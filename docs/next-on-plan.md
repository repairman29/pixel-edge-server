# Next on the Plan (Sovereign Mobile Nexus)

What’s done vs what’s left from the Android 16 edge-server roadmap.

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
| Wakelock / persistence notes | Done (optional-setup.md) |
| **Claude Gateway (AI inference server)** | **Done** (`claude-gateway/`, `scripts/setup-claude-gateway*.sh`) |
| **OpenClaw Heartbeat (AI health monitor)** | **Done** (`scripts/claude-heartbeat.sh`, `scripts/setup-claude-heartbeat.sh`) |

---

## Next (in doc order)

### 1. VNC desktop in the VM (optional)

Run a Linux desktop (e.g. KDE Plasma, GNOME) in the VM and view it via VNC on the phone or from your Mac.

- **In the VM:** Install `tigervnc-standalone-server` and a desktop (e.g. `apt install tigervnc-standalone-server xfce4`), then `vncserver :1`.
- **Port:** 5901. Expose via Tailscale or Terminal app port toggle, then connect with a VNC client to `100.78.73.64:5901` (or Pixel LAN IP).
- **Note:** Pixel 8 Pro uses lavapipe (software GPU) in the VM; GUI will work but not be GPU-accelerated (gfxstream is Pixel 10 only).

See **scripts/setup-vnc-in-vm.sh** (run from Mac) to automate install and first-run steps.

---

### 2. OpenClaw Heartbeat (proactive agent) — ✅ Done via Claude Gateway

The “Jarvis-class” heartbeat now runs through **Claude Gateway’s `/v1/agent` endpoint**.

- Claude autonomously checks thermal, disk, processes, ports, and service health every 30 min.
- Reports are written to `~/claude-gateway/heartbeat.log` on the VM.
- Deploy with `./scripts/setup-claude-heartbeat.sh`.
- See **docs/claude-gateway.md** for full details.

---

### 3. Local LLM in the VM (CPU-bound)

Run a small model inside the Debian VM with Docker or llama.cpp.

- **Docker Model Runner:** In the VM, use Docker to run an OpenAI-compatible LLM server (e.g. `docker run ...` per [Docker Model Runner](https://www.docker.com/blog/run-llms-locally/)). Point OpenClaw at `http://127.0.0.1:port` as the model endpoint.
- **llama.cpp (bare metal):** Build with `-DGGML_SVE=TRUE` for ARM SVE; run a small GGUF (e.g. 3B) for ~12–16 tok/s on the device. Then expose an API or use OpenClaw’s local model config.

See **docs/local-llm-in-vm.md** for minimal steps (Docker Model Runner + optional llama.cpp).

---

### 4. Hybrid NPU inference (VM + Android host)

Use the Tensor NPU on the **Android host** while the agent runs in the **VM**, via ADB.

- **Android host:** Install an app or service that runs MediaPipe LLM Inference (or similar) and accepts prompts (e.g. via local API or `adb shell`).
- **In the VM:** Install ADB, run `adb connect 127.0.0.1:5555` (with host listening for ADB on 5555), then a bridge script in the VM sends prompts to the host (e.g. `adb shell am start ...` or a small server on the host) and reads back tokens.
- **Result:** Orchestration and tools in the VM; heavy inference on the NPU.

See **docs/hybrid-npu-inference.md** for architecture and step-by-step.

---

### 5. 16KB memory pages (optional, destructive) — skipped by default

Can improve memory efficiency and some workloads in the VM.

- **Cost:** Bootloader unlock + factory reset. Not reversible without reflashing.
- **Steps:** Unlock bootloader, enable 16KB page size in Developer options (if available on your build), then factory reset. Only do this if you need maximum VM memory performance and accept the wipe.
- **We do not run this automatically;** it is destructive. Perform manually if you choose.

---

### 6. Homelab-style containers (optional)

The doc mentions CasaOS, Jellyfin, NGINX as examples. You already have Docker; run any of these in the VM as normal containers.

- **CasaOS:** See [CasaOS](https://github.com/IceWhaleTech/CasaOS) for ARM/Docker.
- **Jellyfin:** `docker run -p 8096:8096 jellyfin/jellyfin` (or use docker-compose).
- **NGINX:** `docker run -p 80:80 nginx`.

No extra scripts; use standard Docker commands or compose files.

---

## Summary

| Next item | Effort | Notes |
|-----------|--------|--------|
| ~~Claude Gateway~~ | ~~Done~~ | `claude-gateway/` + `scripts/setup-claude-gateway*.sh` |
| ~~Heartbeat~~ | ~~Done~~ | Claude AI heartbeat via `/v1/agent` + cron |
| VNC desktop | Small | Script + doc; lavapipe only on P8P |
| Local LLM (VM) | Medium | Docker Model Runner or llama.cpp + SVE |
| Hybrid NPU | Medium | Host app + ADB bridge from VM |
| 16KB pages | Optional | Manual; unlock + reset |
| Homelab containers | Small | Use Docker as needed |
