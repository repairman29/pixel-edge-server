#!/usr/bin/env bash
# Build pixel-agent-v2 for the Pixel (aarch64 Linux) and push to device.
# Run from repo root or pixel-edge-server. Requires: Rust, adb, device connected.
# For cross-compile from Mac: install cross (cargo install cross) or use build-in-Termux path.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY_NAME="pixel-agent-v2"
TARGET="aarch64-unknown-linux-gnu"
DEST="/sdcard/jarvis/$BINARY_NAME"

cd "$REPO_DIR/pixel-agent-v2"

# 1. Build for aarch64 Linux
if command -v cross &>/dev/null; then
  echo "Building with cross (Docker)..."
  cross build --release --target "$TARGET"
elif rustup target list --installed | grep -q "$TARGET"; then
  echo "Building with cargo for $TARGET..."
  cargo build --release --target "$TARGET"
else
  echo "No cross-compile setup found."
  echo "  Option A: install cross (uses Docker): cargo install cross"
  echo "  Option B: add target + linker: rustup target add $TARGET, then install aarch64 Linux toolchain (e.g. brew install messense/macos-cross-toolchains/aarch64-unknown-linux-gnu)"
  echo "  Option C: build on the Pixel in Termux: push source, then in Termux run: pkg install rust -y && cd ~/pixel-agent-v2 && cargo build --release"
  exit 1
fi

BIN_PATH="target/$TARGET/release/$BINARY_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Build failed: $BIN_PATH not found"
  exit 1
fi

# 2. Push to device
if ! adb devices | grep -q 'device$'; then
  echo "No device connected. Connect Pixel and enable USB debugging."
  exit 1
fi
echo "Pushing to device $DEST ..."
adb push "$BIN_PATH" "$DEST"
echo "Done. On the Pixel in Termux run:"
echo "  cp /sdcard/jarvis/$BINARY_NAME ~/$BINARY_NAME && chmod +x ~/$BINARY_NAME"
echo "  ./$BINARY_NAME"
