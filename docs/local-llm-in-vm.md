# Local LLM in the VM (CPU-bound)

Run a small LLM inside the Debian VM so Claude Gateway (and OpenClaw) can serve requests without the cloud API. Pixel 8 Pro has no NPU in the VM; inference is CPU-bound with optional ARM SVE acceleration.

## Quick start (automated)

Two one-command paths:

| Goal | Command (from Mac) |
|------|-------------------|
| llama.cpp + SVE (bare metal, fastest) | `bash scripts/setup-llama-sve.sh` |
| Ollama via Docker (easiest model management) | `bash scripts/setup-homelab.sh` |

After either script completes, set `LOCAL_LLM_URL` in the gateway config and restart:

```bash
# For llama-server (setup-llama-sve.sh)
ssh -p 8022 droid@100.78.73.64 \
  "echo 'LOCAL_LLM_URL=http://127.0.0.1:8080/v1/chat/completions' \
   >> ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"

# For Ollama (setup-homelab.sh)
ssh -p 8022 droid@100.78.73.64 \
  "echo 'LOCAL_LLM_URL=http://127.0.0.1:11434/v1/chat/completions' \
   >> ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"
```

Requests using model `"local"` or any `haiku/*` model name will now route to the on-device LLM at zero API cost.

See **[docs/llama-server.md](llama-server.md)** for llama-server detail and **[docs/homelab.md](homelab.md)** for the full homelab (Ollama + Jellyfin + NGINX) stack.

---

## Option A: llama.cpp with SVE (automated, recommended)

`setup-llama-sve.sh` builds llama.cpp in the VM with `DGGML_SVE=ON` for maximum ARM throughput, downloads Llama-3.2-3B-Instruct (Q4_K_M), installs a systemd user service (`llama-server`), and pins inference to the prime core with `taskset -c 0`.

**Expected performance:** ~12–16 tokens/second on a 3B model (Tensor G3, prime core, SVE).

```bash
bash scripts/setup-llama-sve.sh   # run from Mac
```

The service runs at `http://127.0.0.1:8080` inside the VM with an OpenAI-compatible `/v1/chat/completions` endpoint.

To swap the model after initial setup, SSH into the VM and replace the GGUF:

```bash
# In VM: download alternate model
wget -P ~/llama-models/ https://huggingface.co/.../model.gguf
# Update service ExecStart to point at new file, then restart
systemctl --user restart llama-server
```

---

## Option B: Ollama via Docker (easiest model management)

`setup-homelab.sh` brings up the full homelab stack including Ollama with an OpenAI-compatible API at port 11434.

```bash
bash scripts/setup-homelab.sh   # run from Mac
```

**Pull models after stack is running (from VM):**

```bash
docker exec ollama ollama pull llama3.2:3b        # ~2 GB, fast
docker exec ollama ollama pull phi3.5             # ~2.2 GB
docker exec ollama ollama pull mistral:7b-instruct-q4_0  # ~4 GB, slower
```

**Performance:** Slightly lower throughput than bare-metal llama.cpp due to Docker overhead, but model management via `ollama pull/rm` is simpler.

---

## Manual build reference (advanced)

If you need custom CMake flags or want to build from source without the script:

```bash
# In VM
sudo apt install -y build-essential cmake
git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp
cmake -B build -DGGML_SVE=ON
cmake --build build -j$(nproc)

# Run server (pin to prime core, OpenAI-compatible endpoint)
taskset -c 0 ./build/bin/llama-server \
  -m ~/llama-models/llama-3.2-3b-instruct-q4_k_m.gguf \
  --port 8080 --host 127.0.0.1
```

---

## Summary

| Method | Throughput | Model management | Setup |
|--------|-----------|-----------------|-------|
| llama.cpp + SVE (`setup-llama-sve.sh`) | ~12–16 tok/s | Manual GGUF swap | One script |
| Ollama (`setup-homelab.sh`) | ~8–12 tok/s | `ollama pull/rm` | One script |
| Manual build | Same as above | Same as above | Manual |
