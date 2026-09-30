#!/data/data/com.termux/files/usr/bin/bash
# Run this script IN TERMUX on the Pixel to build pixel-agent-v2 from source.
set -e
echo "Building pixel-agent-v2 on device..."

# Allow Termux to read storage (run once; grant when prompted)
termux-setup-storage 2>/dev/null || true

# Find the tarball (Termux may use ~/storage/shared or /sdcard)
SRC_TAR=""
for path in "/sdcard/jarvis/pixel-agent-v2-src.tar.gz" "$HOME/storage/shared/jarvis/pixel-agent-v2-src.tar.gz"; do
  if [ -r "$path" ]; then SRC_TAR="$path"; break; fi
done
if [ -z "$SRC_TAR" ]; then
  echo "Cannot find source tarball. Run: termux-setup-storage (allow access), then try again."
  exit 1
fi

cd ~
rm -rf pixel-agent-v2-src
mkdir -p pixel-agent-v2-src
cd pixel-agent-v2-src
tar -xzf "$SRC_TAR" --strip-components=1
pkg install -y rust 2>/dev/null || true
# One job + no LTO to reduce memory (avoid OOM on device)
export CARGO_BUILD_JOBS=1
cargo build --release 2>&1
cp target/release/pixel-agent-v2 ~/pixel-agent-v2
chmod +x ~/pixel-agent-v2
echo "Done. Binary: ~/pixel-agent-v2"
echo "Run: ./pixel-agent-v2"
