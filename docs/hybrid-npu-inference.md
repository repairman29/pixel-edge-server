# Hybrid NPU Inference (VM + Android Host)

Use the Tensor NPU on the **Android host** for inference while the agent and tools run in the **Debian VM**. The VM sends prompts to the host and receives tokens via ADB or a local socket.

## Architecture

- **VM:** OpenClaw (or your orchestrator), tools, MCP, cron. Runs in the Debian guest.
- **Host:** LLM inference (e.g. MediaPipe LLM Inference API or an app that exposes inference). Has direct access to the Tensor NPU.
- **Bridge:** From the VM, `adb connect 127.0.0.1:5555` to the host, then a small script or service that:
  - Sends the prompt (e.g. `adb shell` to start an activity or call a localhost API on the host),
  - Reads the generated text back (stdout, file, or API response).

## Prerequisites

1. **Android host** runs an inference service that:
   - Listens for requests (e.g. on localhost:5555 or via an activity/broadcast), or
   - Can be driven by `adb shell` (e.g. run an app that reads stdin and prints tokens).
2. **ADB in the VM:** Install `android-tools-adb` (or equivalent) in the Debian VM so the VM can run `adb`.
3. **Host ADB listener:** On the Android device, enable **Wireless debugging** or **ADB over network** so the host listens on 5555. The VM then connects to the host’s loopback (e.g. via vsock or a forwarded port), or the VM and host share a network and the VM uses the host’s IP. If both run on the same device, the VM may reach the host at a special address (e.g. 10.0.2.2 or an address provided by the Terminal/AVF docs). Check Android 16 / AVF docs for “host address from guest”.

## Steps (outline)

1. **On the Android host:** Install and run an app or service that performs LLM inference (e.g. using [MediaPipe LLM Inference](https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android)) and exposes a simple API or CLI that ADB can trigger.
2. **In the VM:** Install ADB, then connect to the host (exact command depends on how the host exposes ADB to the guest; may be `adb connect <host_ip>:5555` or a vsock-based method).
3. **Bridge script in the VM:** A small script (e.g. Python or shell) that:
   - Takes a prompt as input,
   - Calls the host via `adb shell ...` (or curl to host’s local API),
   - Parses the response and prints tokens or the full reply.
4. **OpenClaw:** Configure a “local” model that points to this bridge (e.g. a wrapper that calls your script and returns the model output).

## References

- [MediaPipe LLM Inference - Android](https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android)
- [Bridging Android 16 AVF & Tensor G4: NPU Access from Debian VM](https://www.reddit.com/r/Android/comments/1r1nucx/) (concept applies to Tensor G3 as well)
- Android 16 / AVF docs for “custom VM” or “host-guest networking” to confirm the correct address and method for the VM to reach the host.

This doc is a roadmap; implement the host inference app and VM-side bridge to match your chosen host API.
