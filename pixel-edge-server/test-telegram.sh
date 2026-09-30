#!/data/data/com.termux/files/usr/bin/bash
# Test Telegram API directly

echo "=== Testing Telegram API ==="
echo ""

TOKEN="${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN before running this script}"
CHAT_ID="8705004824"

echo "Testing getMe..."
curl -s "https://api.telegram.org/bot${TOKEN}/getMe"

echo ""
echo ""
echo "Testing sendMessage..."
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\":${CHAT_ID},\"text\":\"Test from curl\"}"

echo ""
echo ""
echo "=== Done ==="
