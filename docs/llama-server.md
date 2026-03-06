# llama-server (ARM SVE — Tensor G3)

On-device LLM inference inside the Debian VM, built from [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) with ARM SVE enabled for the Tensor G3 (Cortex-X3 prime core).

## Setup

```bash
bash scripts/setup-llama-sve.sh   # run from Mac — ~10–20 min first time
```

**What the script does (4 steps):**

1. Clones/updates llama.cpp in the VM and builds with `DGGML_SVE=ON -march=armv9-a+sve`
2. Downloads Llama-3.2-3B-Instruct Q4_K_M (~2 GB) to `~/llama-models/`
3. Installs a systemd user service (`llama-server`) on port `8080` with `Restart=on-failure`
4. Sets `LOCAL_LLM_URL` in the Claude Gateway `.env` and restarts the gateway

**Environment overrides:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `PIXEL_HOST` | `droid@100.78.73.64` | SSH target |
| `PIXEL_PORT` | `8022` | SSH port |
| `MODEL_URL` | Llama-3.2-3B-Instruct Q4_K_M (HuggingFace) | GGUF download URL |
| `MODEL_NAME` | `Llama-3.2-3B-Instruct-Q4_K_M.gguf` | Local filename |
| `SERVE_PORT` | `8080` | llama-server port |
| `LINK_GATEWAY` | `1` | Auto-set `LOCAL_LLM_URL` in Claude Gateway |

---

## Performance

Tested on Pixel 8 Pro (Tensor G3), Llama-3.2-3B Q4_K_M, pinned to prime core (Cortex-X3):

| Model | Size | Tok/s (approx) |
|-------|------|----------------|
| Llama-3.2-3B Q4_K_M | ~2 GB | ~12–16 tok/s |
| Phi-3.5-mini Q4_K_M | ~2.2 GB | ~10–14 tok/s |
| Mistral-7B Q4_0 | ~4 GB | ~4–7 tok/s |

SVE adds ~15–20% throughput over a non-SVE build on A715/X3 cores.

---

## API

The service exposes an OpenAI-compatible endpoint:

```bash
# Direct test (bypass Claude Gateway)
curl http://100.78.73.64:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"local","messages":[{"role":"user","content":"Hello!"}],"max_tokens":128}'

# Via Claude Gateway (model "local" or "haiku/*" routes here)
curl http://100.78.73.64:3456/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"local","messages":[{"role":"user","content":"Hello!"}]}'
```

---

## Service Management

```bash
# Status
ssh -p 8022 droid@100.78.73.64 'systemctl --user status llama-server'

# Restart
ssh -p 8022 droid@100.78.73.64 'systemctl --user restart llama-server'

# Logs (live)
ssh -p 8022 droid@100.78.73.64 'tail -f ~/llama-server.log'

# Stop
ssh -p 8022 droid@100.78.73.64 'systemctl --user stop llama-server'
```

---

## Swapping Models

1. Download a new GGUF to `~/llama-models/` in the VM:

   ```bash
   ssh -p 8022 droid@100.78.73.64 \
     "wget -P ~/llama-models/ https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"
   ```

2. Edit the launch wrapper to point at the new file:

   ```bash
   ssh -p 8022 droid@100.78.73.64 \
     "sed -i 's|--model ~/llama-models/.*|--model ~/llama-models/Phi-3.5-mini-instruct-Q4_K_M.gguf \\\\|' ~/bin/llama-serve.sh"
   ```

3. Restart the service:

   ```bash
   ssh -p 8022 droid@100.78.73.64 'systemctl --user restart llama-server'
   ```

---

## Rebuild After llama.cpp Update

```bash
# Re-run setup script — it fetches latest llama.cpp and rebuilds; model download is skipped if file exists
bash scripts/setup-llama-sve.sh
```

---

## Architecture Note

llama-server runs directly in the Debian VM (not in Docker) so it can pin to the Tensor G3 prime core via `taskset -c 0` in the launch wrapper. It is separate from the Ollama container in the homelab stack — see **[docs/homelab.md](homelab.md)** if you prefer Docker-managed models.
