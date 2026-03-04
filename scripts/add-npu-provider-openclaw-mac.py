#!/usr/bin/env python3
"""Merge npu-bridge provider into ~/.openclaw/openclaw.json (create file/dir if needed). Run on your Mac."""
import json
import os

OPENCLAW_DIR = os.path.expanduser("~/.openclaw")
OPENCLAW_JSON = os.path.join(OPENCLAW_DIR, "openclaw.json")
NPU_SHIM_PORT = os.environ.get("NPU_SHIM_PORT", "9190")

NPU_PROVIDER = {
    "npu-bridge": {
        "baseUrl": f"http://127.0.0.1:{NPU_SHIM_PORT}",
        "api": "openai-completions",
        "models": [
            {
                "id": "pixel-npu",
                "name": "Pixel NPU (host)",
                "contextWindow": 4096,
                "maxTokens": 512,
                "reasoning": False,
                "input": ["text"],
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            }
        ],
    }
}

def main():
    os.makedirs(OPENCLAW_DIR, exist_ok=True)
    if os.path.exists(OPENCLAW_JSON):
        with open(OPENCLAW_JSON) as f:
            data = json.load(f)
    else:
        data = {}

    providers = data.setdefault("models", {}).setdefault("providers", {})
    if "npu-bridge" in providers:
        providers["npu-bridge"] = NPU_PROVIDER["npu-bridge"]
        print("Updated npu-bridge provider in ~/.openclaw/openclaw.json")
    else:
        providers["npu-bridge"] = NPU_PROVIDER["npu-bridge"]
        print("Added npu-bridge provider to ~/.openclaw/openclaw.json")

    with open(OPENCLAW_JSON, "w") as f:
        json.dump(data, f, indent=2)

    print(f"baseUrl: http://127.0.0.1:{NPU_SHIM_PORT}")
    print("Model id: npu-bridge/pixel-npu — select 'Pixel NPU (host)' in Mission Control.")

if __name__ == "__main__":
    main()
