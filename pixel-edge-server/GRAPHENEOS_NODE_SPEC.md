# Pixel 8 Edge Node: GrapheneOS Architecture & Fleet Specification

> **STAGING: PRIVATE-UNTIL-FLIP (TASK-125 / TASK-126 PREPARATION)**  
> **ARCHITECTURAL DECISION RECORD (ADR-2026-10-13):** Ratified to remain on **GrapheneOS** on the Google Pixel 8 Pro. Do not flash to stock Android.

---

## 1. Architectural Decision Record (ADR)

### Context
The autonomous fleet requires an edge computing node that survives network partitions, provides physical sensor telemetry (camera vision, ambient status), offers out-of-band communication (cellular SMS alerts when broadband WAN is severed), and executes local inference. The primary edge hardware is a **Google Pixel 8 Pro** (Tensor G3, 12 GB RAM, ARMv9 Cortex-X3 + A715 + A520, Mali-G715 GPU). The device currently runs **GrapheneOS**.

### Decision
**We remain on GrapheneOS.** We explicitly reject reflashing to stock Google Android.

### Rationale & Tradeoffs
1. **Server Stability vs. Unscheduled Reboots:** Stock Android aggressively forces monthly Google system and Play system reboots that terminate long-running server daemons without notice. GrapheneOS gives the operator complete control over updates with zero unsolicited reboots.
2. **Telemetry & Network Cleanliness:** Stock Android runs dozens of background Google Play Services sync tasks that consume cellular bandwidth, spike CPU thermals, and leak metadata. GrapheneOS is completely quiet; every packet transmitted across WiFi/Tailscale is intentional.
3. **Tradeoff Accepted (Tensor G3 AICore):** On GrapheneOS, Google's proprietary `AICore` system service (which powers Gemini Nano via proprietary system signatures) is inoperable. We accept this trade because proprietary system models cannot be customized or fine-tuned anyway. Instead, we run open-weights models (Qwen 2.5 0.5B/1.5B, Gemma 2 2B) through **`llama.cpp`** on CPU (ARM Neon) and Mali-G715 GPU (Vulkan).
4. **Security Hardening:** GrapheneOS’s hardened memory allocator (`hardened_malloc`), exec sandboxing, and strict network/sensor permission controls make the edge device virtually immune to remote malicious takeover if exposed as a network node.

---

## 2. GrapheneOS Operational Runbook & Hardening Configuration

To transform a GrapheneOS phone from a personal handheld into a 24/7 autonomous edge server, the following four system configurations and two ADB overrides are mandatory:

```
┌────────────────────────────────────────────────────────────────────────┐
│               MANDATORY GRAPHENEOS SERVER CONFIGURATION               │
├────────────────────┬───────────────────────────────────────────────────┤
│ 1. USB Data Lock   │ Settings -> Security -> USB peripherals           │
│                    │ Set to: "Allow new USB peripherals" (Always)      │
├────────────────────┼───────────────────────────────────────────────────┤
│ 2. Battery Sleep   │ Settings -> Apps -> Termux (and Jarvis) ->        │
│                    │ Battery -> Set to: "Unrestricted"                 │
├────────────────────┼───────────────────────────────────────────────────┤
│ 3. Network Access  │ Settings -> Apps -> Termux -> Permissions ->      │
│                    │ Network -> Set to: "Allowed"                      │
├────────────────────┼───────────────────────────────────────────────────┤
│ 4. CPU Wake Lock   │ Run inside Termux: `termux-wake-lock`             │
│                    │ Holds partial wake lock; screen off does not sleep│
└────────────────────┴───────────────────────────────────────────────────┘
```

### Automated ADB Pre-Flight Script (`prep-graphene-node.sh`)
Execute from the Mac workstation when the Pixel is connected via USB:

```bash
#!/usr/bin/env bash
# prep-graphene-node.sh — Disable Android 14 process killers & prep GrapheneOS node
set -euo pipefail

echo "== Checking ADB connection..."
adb wait-for-device
DEVICE=$(adb shell getprop ro.product.model | tr -d '\r')
BUILD=$(adb shell getprop ro.build.display.id | tr -d '\r')
echo "Connected to: $DEVICE ($BUILD)"

echo "== Disabling Android 14 Phantom Process Killer..."
# Prevents Android from killing child processes spawned in Termux exceeding 32 procs
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647" || true
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent" || true

echo "== Granting Termux & Termux:API permissions..."
adb shell "pm grant com.termux android.permission.POST_NOTIFICATIONS" || true
adb shell "pm grant com.termux.api android.permission.SEND_SMS" || true
adb shell "pm grant com.termux.api android.permission.CAMERA" || true
adb shell "pm grant com.termux.api android.permission.ACCESS_FINE_LOCATION" || true

echo "== Configuring Port Forwarding (Host -> Pixel)..."
# Port 18790: pixel-agent-v2 gateway (avoiding Maclawd 18789 collision)
# Port 9090: local model HTTP API (Jarvis / llama.cpp)
adb forward tcp:18790 tcp:18790
adb forward tcp:9090 tcp:9090

echo "== Pixel 8 GrapheneOS Edge Node is prepped and forwarded."
```

---

## 3. Hardware Acceleration & Inference Strategy

Without Google AICore, the Pixel 8 Pro utilizes its native raw hardware via open-source engines:

```
┌────────────────────────────────────────────────────────┐
│            PIXEL 8 PRO HARDWARE ALLOCATION             │
├───────────────────────┬────────────────────────────────┤
│ CPU: Cortex-X3 (1x)   │ Primary LLM thread & orchestrator│
│      Cortex-A715 (4x) │ High-speed token generation    │
│      Cortex-A520 (4x) │ Background NATS bus & telemetry│
├───────────────────────┼────────────────────────────────┤
│ GPU: Mali-G715 (10c)  │ Vulkan backend via llama.cpp   │
├───────────────────────┼────────────────────────────────┤
│ RAM: 12 GB LPDDR5X    │ 4 GB OS/Apps, 8 GB Model Cache │
└───────────────────────┴────────────────────────────────┘
```

### Approved On-Device Model Matrix

| Model | Format / Quant | Engine | Inference Speed | Primary Fleet Role |
| :--- | :--- | :--- | :--- | :--- |
| **Qwen 2.5 0.5B Instruct** | GGUF (`Q8_0` or `Q4_K_M`) | `llama.cpp` (CPU) | **45 – 60 tok/s** | Ultra-fast routing, JSON structuring, intent classification |
| **Qwen 2.5 1.5B Instruct** | GGUF (`Q4_K_M`) | `llama.cpp` (CPU/Vulkan) | **25 – 35 tok/s** | Primary edge agent reasoning, tool call generation |
| **Gemma 2 2B Instruct** | GGUF (`Q4_K_M`) | `llama.cpp` (Vulkan) | **16 – 22 tok/s** | Deep code triage, offline reasoning |
| **MiniCPM-V 2.6** | GGUF (`Q4_K_M`) | `llama-mtp` / native | **8 – 12 tok/s** | Multimodal camera inspection & physical document OCR |

---

## 4. Fleet Bus Integration & Communication Protocol

The Pixel edge node participates in the fleet as a first-class citizen alongside IDE agents (`antigravity`, `mac-opencode`, `claude`):

### NATS Mesh Registration
- **Agent Name:** `pixel-8-alpha`
- **Tailscale IP:** Node connects directly to the private tailnet mesh.
- **Inbound Topics:** `agents.bus.pixel-8-alpha.*`, `chat.ch.edge`
- **Heartbeat Cadence:** Emits `edge_heartbeat_tick` every 60 seconds with battery temperature, charging state, and local RAM usage.

### Physical Out-of-Band Alerting (SMS & Telephony)
If broadband connectivity to the central hub fails:
1. `duty-agent` or the local watchdog detects gateway timeout ($> 120\text{s}$).
2. Node triggers cellular dispatch via Termux:API:
   ```bash
   termux-sms-send -n "+1XXXXXXXXXX" "FLEET-ALERT: Broadband link down on closetjunky. Pixel edge node active on LTE."
   ```
3. Outbound confirmation is mirrored to the local append-only log.

### Port Allocation Architecture
To eliminate port collisions between the host Mac and the Pixel:

| Port | Bound Environment | Purpose | Protocol |
| :---: | :--- | :--- | :--- |
| **18789** | Host Mac (Maclawd) | MacBook local agent gateway | HTTP REST |
| **18790** | Pixel (GrapheneOS) | `pixel-agent-v2` edge gateway | HTTP REST / FastMCP |
| **9090** | Pixel (GrapheneOS) | Local on-device LLM server | OpenAI-compatible HTTP |
| **4222** | Fleet Hub | NATS event message broker | TCP |

---

## 5. Multi-Node Edge Scaling Pipeline (`TASK-126` Preview)

When scaling from 1 phone to an array of $N$ Pixels (e.g., Pixel 8, Pixel 7, Pixel 6a):
1. **Zero Manual Setup:** The phone is flashed with GrapheneOS via the official web installer.
2. **Automated Bootstrapping:** A single shell script (`ONE_LINER_SETUP.sh`) is piped over ADB:
   - Sets up Termux and installs Python, Rust, Git, and Tailscale.
   - Pushes the precompiled `pixel-agent-v2` ARM64 binary.
   - Assigns a deterministic node ID (`pixel-node-01`, `pixel-node-02`) derived from the hardware serial number.
   - Registers the node onto the NATS fleet bus.

---

## 6. Action Items for Live Hardware Session

When ready to dock and configure the physical Pixel 8:
- [ ] Connect device via USB-C cable to host Mac.
- [ ] Verify `adb devices` reports `device` (not `unauthorized` or empty).
- [ ] Execute `launch/scripts/prep-graphene-node.sh` to apply permissions and disable phantom killers.
- [ ] Start Termux, run `termux-wake-lock`, and start `pixel-agent-v2`.
- [ ] Broadcast handshake on NATS: `broadcast "edge.joined" {"node": "pixel-8-alpha"}`.
