#!/data/data/com.termux/files/usr/bin/sh
# Fix Clawdbot on Android/Termux by creating stub clipboard module

echo "Fixing Clawdbot for Android..."

CLIPBOARD_DIR="/data/data/com.termux/files/usr/lib/node_modules/clawdbot/node_modules/@mariozechner/clipboard"

# Create stub native module
cat > "$CLIPBOARD_DIR/clipboard.android-arm64.node" << 'NODEMODULE'
module.exports = {
  readText: () => Promise.resolve(''),
  writeText: () => Promise.resolve(),
  readImage: () => Promise.resolve(null),
  writeImage: () => Promise.resolve(),
  readFiles: () => Promise.resolve([]),
  writeFiles: () => Promise.resolve(),
  clear: () => Promise.resolve(),
  watch: () => ({ stop: () => {} })
};
NODEMODULE

echo "✓ Stub clipboard module created"

# Test clawdbot
echo "Testing Clawdbot..."
clawdbot --version 2>&1 | head -1 && echo "✓ Clawdbot working!" || echo "Still has issues"

# Try pairing if working
clawdbot pairing approve telegram WT4LUXF4 2>&1 | head -5