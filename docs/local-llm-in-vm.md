# Local LLM in the VM (CPU-bound)

Run a small LLM inside the Debian VM so OpenClaw can use it without the cloud. Pixel 8 Pro has no NPU in the VM; inference is CPU-bound (and optionally SVE-accelerated on ARM).

## Option A: Docker Model Runner

Docker can serve an OpenAI-compatible API from a container.

1. **In the VM**, pull and run a small model (e.g. Phi or TinyLlama) per [Docker Model Runner](https://www.docker.com/blog/run-llms-lally/). Example (adjust image/tag for ARM64):

   ```bash
   docker run -d --name llm -p 11434:11434 ...
   ```

   Use an image that supports `linux/arm64`. If the official Model Runner image is x86-only, search for an ARM-compatible Ollama or llama.cpp server image.

2. **In OpenClaw**, set the model endpoint to `http://127.0.0.1:11434/v1` (or whatever port the container exposes).

3. **Performance:** Expect a few tokens per second for small models (e.g. 1–3B params) on the Tensor G3 CPU.

## Option B: llama.cpp with SVE (bare metal)

For best CPU throughput on ARM, build llama.cpp in the VM with SVE enabled.

1. **In the VM:**
   ```bash
   sudo apt install -y build-essential cmake
   git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp
   cmake -B build -DGGML_SVE=ON
   cmake --build build -j
   ```

2. Download a small GGUF (e.g. 3B) and run the server:
   ```bash
   ./build/bin/llama-server -m model.gguf --port 8080
   ```

3. Point OpenClaw at `http://127.0.0.1:8080` (or use the OpenAI-compatible endpoint if the build supports it).

4. **Taskset:** Pin to the prime core for lower latency: `taskset -c 0 ./build/bin/llama-server ...`.

## Summary

| Method | Pros | Cons |
|--------|------|------|
| Docker Model Runner | Easy, OpenAI-compatible | Need ARM image; may be slower |
| llama.cpp + SVE | Fast on ARM, full control | Build and config in VM |

After one of these is running, configure OpenClaw to use the local endpoint as the default or an optional model.
