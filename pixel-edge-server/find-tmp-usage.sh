#!/data/data/com.termux/files/usr/bin/bash
# Find where /tmp is used

echo "=== Finding /tmp usage ==="
echo ""

cd ~/JARVIS

# Search for tmpdir, mkdtemp, or /tmp
echo "Searching node_modules for tmp references..."
grep -r "require.*os" node_modules/@anthropic-ai/ 2>/dev/null | head -5

echo ""
echo "Searching for tmp in gateway..."
find node_modules -name "*gateway*" -type f 2>/dev/null | head -10

echo ""
echo "Looking for clawdbot package.json..."
find node_modules -name "package.json" -path "*clawdbot*" 2>/dev/null | head -5

echo ""
echo "Checking main entry..."
cat node_modules/.bin/clawdbot 2>/dev/null | head -10

echo ""
echo "=== Done ==="
