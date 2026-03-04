#!/usr/bin/env bash
# Download the GPU model used by MediaPipe LLM Inference (GEMMA_3_1B_IT_GPU) and push to the Pixel.
# Run from your Mac with the Pixel connected via USB.
#
# The model is gated: accept the Gemma license at
#   https://huggingface.co/litert-community/Gemma3-1B-IT
# then create a token at https://huggingface.co/settings/tokens and set HF_TOKEN:
#   export HF_TOKEN="hf_..."
#
# Usage:
#   ./scripts/download-and-push-gpu-model.sh
# Or put your token in a gitignored file (so it's never committed):
#   echo "hf_xxx" > .hf-token
#   ./scripts/download-and-push-gpu-model.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use HF_TOKEN from env, or from project .hf-token file (gitignored)
if [ -z "${HF_TOKEN:-}" ] && [ -f "$PROJECT_DIR/.hf-token" ]; then
  HF_TOKEN=$(cat "$PROJECT_DIR/.hf-token")
fi
MODEL_URL="https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q8_ekv2048.task"
MODEL_FILE="Gemma3-1B-IT_multi-prefill-seq_q8_ekv2048.task"
DEVICE_PATH="/data/local/tmp/$MODEL_FILE"
LOCAL_FILE="${PROJECT_DIR}/.cache/$MODEL_FILE"

echo "GPU model: $MODEL_FILE (GEMMA_3_1B_IT_GPU)"
echo ""

# Download on Mac
mkdir -p "$(dirname "$LOCAL_FILE")"
if [ -f "$LOCAL_FILE" ]; then
  echo "Using cached file: $LOCAL_FILE"
else
  echo "Downloading from Hugging Face (may require HF_TOKEN for gated model)..."
  if [ -n "${HF_TOKEN:-}" ]; then
    curl -L -f -H "Authorization: Bearer $HF_TOKEN" -o "$LOCAL_FILE" "$MODEL_URL"
  else
    curl -L -f -o "$LOCAL_FILE" "$MODEL_URL" || {
      echo ""
      echo "Download failed. If the model is gated:"
      echo "  1. Open https://huggingface.co/litert-community/Gemma3-1B-IT and accept the license."
      echo "  2. Create a token at https://huggingface.co/settings/tokens"
      echo "  3. Run: HF_TOKEN=hf_xxx $0"
      exit 1
    }
  fi
  echo "Downloaded to $LOCAL_FILE"
fi

# Push to device
echo ""
echo "Pushing to device at $DEVICE_PATH ..."
adb push "$LOCAL_FILE" "$DEVICE_PATH" || {
  echo ""
  echo "adb push failed. Some devices restrict /data/local/tmp."
  echo "You can try: adb root (if available), or use the in-app download with a working Hugging Face token."
  exit 1
}

echo ""
echo "Done. In the LLM Inference app:"
echo "  1. Select model: GEMMA_3_1B_IT_GPU"
echo "  2. The app should find the file at $DEVICE_PATH and load without downloading."
echo "  3. Open the chat screen and test: curl -X POST http://127.0.0.1:9090/infer ... (after adb forward tcp:9090 tcp:9090)"
