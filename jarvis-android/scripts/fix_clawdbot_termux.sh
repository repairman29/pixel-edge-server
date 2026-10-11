#!/data/data/com.termux/files/usr/bin/sh
# Fix Clawdbot on Android using Termux API approach

echo "Fixing Clawdbot for Android with Termux API..."

CLIPBOARD_DIR="/data/data/com.termux/files/usr/lib/node_modules/clawdbot/node_modules/@mariozechner/clipboard"

# Create a proper Node.js stub that uses Termux API
cat > "$CLIPBOARD_DIR/index.js" << 'EOF'
const { execSync } = require('child_process');

function readText() {
  try {
    return execSync('termux-clipboard-get 2>/dev/null || echo ""', { encoding: 'utf8' }).trim();
  } catch (e) {
    return '';
  }
}

function writeText(text) {
  try {
    execSync(`termux-clipboard-set "${text.replace(/"/g, '\\"')}" 2>/dev/null`);
    return true;
  } catch (e) {
    return false;
  }
}

function readImage() {
  return Promise.resolve(null);
}

function writeImage() {
  return Promise.resolve();
}

function readFiles() {
  return Promise.resolve([]);
}

function writeFiles() {
  return Promise.resolve();
}

function clear() {
  return writeText('');
}

function watch() {
  return { stop: () => {} };
}

module.exports = {
  readText: () => Promise.resolve(readText()),
  writeText: (text) => Promise.resolve(writeText(text)),
  readImage,
  writeImage,
  readFiles,
  writeFiles,
  clear: () => Promise.resolve(clear()),
  watch
};
EOF

echo "✓ Patched clipboard module with Termux API"

# Remove any compiled native modules that might conflict
rm -f "$CLIPBOARD_DIR"/*.node

echo "✓ Removed conflicting native modules"

# Test clawdbot
echo ""
echo "Testing Clawdbot..."
clawdbot --version 2>&1 && echo "✓ Clawdbot is working!" || echo "✗ Still has issues"

echo ""
echo "Attempting to approve pairing..."
clawdbot pairing approve telegram <PAIRING_CODE> 2>&1 | head -10