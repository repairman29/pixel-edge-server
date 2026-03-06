# Homelab Stack (Pixel 8 Pro)

Three Docker services running in the Debian VM, managed by `homelab/docker-compose.yml`.

## Deploy

```bash
bash scripts/setup-homelab.sh   # run from Mac — copies files, starts stack
```

Or manually from inside the VM:

```bash
cd ~/homelab && docker compose up -d
docker compose ps
```

---

## Services & Ports

| Service | Port | URL (Tailscale) | Purpose |
|---------|------|-----------------|---------|
| Ollama | `11434` | `http://100.78.73.64:11434` | Local LLM inference (OpenAI-compatible) |
| Jellyfin | `8096` | `http://100.78.73.64:8096` | Media server |
| NGINX | `80` | `http://100.78.73.64` | Reverse proxy (see routes below) |

**NGINX routes** (all via port 80):

| Path | Proxies to |
|------|-----------|
| `/` | Jellyfin `:8096` |
| `/ollama/` | Ollama `:11434` |
| `/ai/` | Claude Gateway `:3456` (VM host, not in Docker) |

---

## Ollama — Model Management

```bash
# Pull models (from VM after stack is running)
docker exec ollama ollama pull llama3.2:3b        # ~2 GB, fast (~8–12 tok/s)
docker exec ollama ollama pull phi3.5             # ~2.2 GB, good for coding
docker exec ollama ollama pull mistral:7b-instruct-q4_0  # ~4 GB, slower

# List loaded models
docker exec ollama ollama list

# Remove a model
docker exec ollama ollama rm mistral:7b-instruct-q4_0
```

**Memory note:** The compose file caps Ollama at 6 GB RAM (`memory: 6g`). Stick to models ≤4 GB GGUF to stay safe. The Tensor G3 has 12 GB LPDDR5 shared with the VM; the VM typically uses 2–3 GB leaving ~6 GB for Ollama.

**Route Claude Gateway traffic to Ollama:**

```bash
ssh -p 8022 droid@100.78.73.64 \
  "echo 'LOCAL_LLM_URL=http://127.0.0.1:11434/v1/chat/completions' \
   >> ~/.config/claude-gateway/.env && \
   systemctl --user restart claude-gateway"
```

Requests to the gateway with model `"local"` or any `haiku/*` name will route to Ollama.

---

## Jellyfin — First Run

1. Open `http://100.78.73.64:8096` in your browser
2. Follow the setup wizard (create admin account, pick language)
3. Add a library pointing at `/media` (mount Android shared storage or a VM path)

To mount Android shared storage into the VM (path varies by build; check AVF docs), uncomment the volume in `docker-compose.yml`:

```yaml
# - /mnt/media:/media:ro
```

---

## Useful Commands

```bash
# Stack status
ssh -p 8022 droid@100.78.73.64 'cd ~/homelab && docker compose ps'

# Follow all logs
ssh -p 8022 droid@100.78.73.64 'cd ~/homelab && docker compose logs -f'

# Restart a single service
ssh -p 8022 droid@100.78.73.64 'docker restart ollama'

# Stop entire stack
ssh -p 8022 droid@100.78.73.64 'cd ~/homelab && docker compose down'

# Upgrade images
ssh -p 8022 droid@100.78.73.64 'cd ~/homelab && docker compose pull && docker compose up -d'
```

---

## Optional: Add Grafana

Grafana is not in the default compose file. To add it, append to `homelab/docker-compose.yml`:

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

Add `grafana_data:` under the `volumes:` key at the bottom, then `docker compose up -d grafana`. Add Claude Gateway as a Prometheus data source pointing at `http://100.78.73.64:3456/metrics`.
