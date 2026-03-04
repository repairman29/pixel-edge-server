# NPU Setup Checklist — What You Do vs What’s Automated

Get the Pixel’s Tensor NPU serving Jarvis with a clear split: **you** do the Android app once; **scripts** do the VM and OpenClaw wiring.

**When to do what**

| When | You do | Then |
|------|--------|------|
| **First time** | 1. Clone MediaPipe sample, open in Android Studio, Run on Pixel. 2. Add `HttpLlmServer.kt` + NanoHTTPD, start server in app, test with `adb shell curl`. | Run `./scripts/setup-npu-openclaw.sh` from your Mac. |
| **Daily use** | Start the LLM Inference app on the Pixel (and keep it in foreground or allow background). | Jarvis can use model **npu-bridge/pixel-npu** in Mission Control. |

---

## Phase 1: You do this (one-time)

**New to Android?** Use the detailed **[Android NPU beginner walkthrough](android-npu-beginner-walkthrough.md)** for step-by-step instructions (developer options, USB debugging, where to add files, and exactly where to start the server in the sample).

### Step 1.1 — Clone the MediaPipe sample and open in Android Studio

On your Mac:

```bash
cd ~/Projects  # or wherever you keep code
git clone https://github.com/google-ai-edge/mediapipe-samples
```

1. Open **Android Studio**.
2. **File → Open** → select `mediapipe-samples/examples/llm_inference/android`.
3. Let Gradle sync (may take a few minutes).
4. Plug in your Pixel (USB). Enable **USB debugging** if prompted.
5. Click **Run** (green triangle) to build and install the app on the Pixel.
6. On the phone: open the **LLM Inference** app, download a small model (e.g. Gemma 2B) if the app asks, and confirm it can generate text once from the UI.

You now have the official sample running on the Pixel. Next we add the HTTP server so the VM can call it.

### Step 1.2 — Add the HTTP server to the sample

We provide a single file that adds a local HTTP endpoint to the app. You’ll add it to the same Android project and start it from the main screen.

1. In Android Studio, in the **app** module, create a new Kotlin file (or use the one we added to this repo):
   - Path: `app/src/main/java/com/google/mediapipe/examples/llminference/HttpLlmServer.kt`
   - Contents: copy from **`android-npu-server/HttpLlmServer.kt`** in this repo (`pixel-edge-server/android-npu-server/HttpLlmServer.kt`).

2. Add the **NanoHTTPD** dependency to `app/build.gradle.kts` (in the `dependencies { }` block):

   ```kotlin
   implementation("org.nanohttpd:nanohttpd:2.3.1")
   ```

3. In the sample’s **MainActivity** (or wherever the UI is created), start the server when the app is ready (e.g. in `onCreate` or after the model is loaded). You need to pass a lambda or function that takes a prompt `String` and returns the generated `String` (using the app’s existing LLM inference). Example:

   ```kotlin
   // Start HTTP server on port 9090 so the VM can call us via adb shell curl
   llmServer = HttpLlmServer(9090) { prompt -> yourLlmInference.generateResponse(prompt) }
   llmServer.start()
   ```

4. Rebuild and **Run** again on the Pixel. Leave the app in the foreground (or ensure it’s not killed) so the server keeps running.

5. **Quick test from your Mac** (Pixel plugged in, app running):

   ```bash
   adb shell "curl -sS -X POST http://127.0.0.1:9090/infer -H 'Content-Type: application/json' -d '{\"prompt\":\"Say hello in one word.\"}'"
   ```

   You should get back a JSON object with generated text. If that works, the host side is done.

---

## Phase 2: OpenClaw (VM or Mac)

Once the Android app is serving HTTP on port 9090 you can wire it to OpenClaw in one of two ways.

### Option A — VM (when SSH/terminal to the Pixel VM works)

From your Mac (with Tailscale or USB to the Pixel VM):

1.

   ```bash
   cd /Users/jeffadkins/Projects
   ./scripts/setup-npu-openclaw.sh
   ```

   This script:

   - Deploys **npu-bridge.sh** (calls `adb shell curl http://127.0.0.1:9090/infer`).
   - Deploys the **OpenClaw NPU shim** (small HTTP server in the VM that turns NPU responses into OpenAI-format for OpenClaw).
   - Adds the **npu-bridge** model provider to `~/.openclaw/openclaw.json`.
   - Restarts the gateway.

2. **Optional:** In Mission Control or in config, set the default model to **npu-bridge/pixel-npu** so Jarvis uses the NPU by default. Otherwise you can switch to it per-session.

3. **Test from Telegram/Discord:** Send a short prompt to Jarvis; it should be answered by the NPU-backed model.

### Option B — Mac-only (when the Pixel VM/terminal isn’t available)

If you can’t SSH into the VM or the terminal on the Pixel is failing, run the NPU shim on your Mac and point OpenClaw (running on the Mac) at it:

1. **Forward the app port and start the shim:**
   ```bash
   adb forward tcp:9090 tcp:9090
   cd ~/Projects
   ./scripts/run-npu-shim-on-mac.sh
   ```
   Leave this running. The shim listens on http://127.0.0.1:9190.

2. **In OpenClaw** (on your Mac), add or edit the NPU provider so `baseUrl` is `http://127.0.0.1:9190` and the model id is `npu-bridge/pixel-npu` (or add that provider if it’s not there). Then choose that model in Mission Control.

3. Keep the LLM Inference app on the Pixel on the chat screen (and USB connected) while using the NPU model.

---

## Summary

| Step | Who | What |
|------|-----|------|
| 1.1 | You | Clone mediapipe-samples, open in Android Studio, Run on Pixel, confirm LLM works in UI |
| 1.2 | You | Add HttpLlmServer.kt + NanoHTTPD, start server in MainActivity, test with adb shell curl |
| 2 | You (run script) | Run ./scripts/setup-npu-openclaw.sh; Jarvis can then use npu-bridge/pixel-npu |

If anything in Phase 1 fails (build errors, app crashes, curl returns nothing), fix that before running Phase 2. The VM side assumes the host responds at `http://127.0.0.1:9090/infer`.
