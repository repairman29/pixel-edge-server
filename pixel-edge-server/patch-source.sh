#!/data/data/com.termux/files/usr/bin/bash
# Patch clawdbot source to use ~/tmp instead of /tmp

echo "=== Patching Clawdbot Source ==="
echo ""

cd ~/JARVIS

# Find where /tmp is used
echo "Searching for /tmp references in clawdbot..."
grep -r "'/tmp'" node_modules/@anthropic-ai/ 2>/dev/null | head -10

echo ""
echo "Searching for os.tmpdir..."
grep -r "os.tmpdir" node_modules/@anthropic-ai/ 2>/dev/null | head -10

echo ""
echo "Searching for mkdtemp..."
grep -r "mkdtemp" node_modules/@anthropic-ai/ 2>/dev/null | head -10

echo ""
echo "Finding clawdbot entry point..."
find node_modules/@anthropic-ai/ -name "*.js" -type f | head -10

echo ""
echo "Attempting to find and replace..."

# Try to find the main file
if [ -f "node_modules/@anthropic-ai/sdk/dist/index.js" ]; then
    echo "Found sdk/dist/index.js"
    grep -n "/tmp" node_modules/@anthropic-ai/sdk/dist/index.js | head -5
fi

echo ""
echo "Creating patched version..."
