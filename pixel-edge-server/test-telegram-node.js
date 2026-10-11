#!/data/data/com.termux/files/usr/bin/env node
// Test Telegram API with fetch

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const CHAT_ID = "<YOUR_TELEGRAM_CHAT_ID>";

console.log("=== Testing Telegram API ===\n");

// Test getMe
console.log("Testing getMe...");
fetch(`https://api.telegram.org/bot${TOKEN}/getMe`)
  .then(res => res.json())
  .then(data => {
    console.log("getMe response:", JSON.stringify(data, null, 2));
    console.log("\nTesting sendMessage...");
    
    // Test sendMessage
    return fetch(`https://api.telegram.org/bot${TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: CHAT_ID,
        text: "Test message from Node.js"
      })
    });
  })
  .then(res => res.json())
  .then(data => {
    console.log("sendMessage response:", JSON.stringify(data, null, 2));
    console.log("\n=== Done ===");
  })
  .catch(err => {
    console.error("Error:", err);
    process.exit(1);
  });
