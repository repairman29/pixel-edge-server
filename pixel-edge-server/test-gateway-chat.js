#!/data/data/com.termux/files/usr/bin/env node
// Test gateway chat without auth

const http = require('http');

const postData = JSON.stringify({
  model: "gpt-4o-mini",
  messages: [
    { role: "user", content: "Hello" }
  ]
});

const options = {
  hostname: '127.0.0.1',
  port: 18789,
  path: '/v1/chat/completions',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(postData)
  }
};

console.log("Testing gateway chat without auth...");

const req = http.request(options, (res) => {
  console.log(`Status: ${res.statusCode}`);
  console.log(`Headers: ${JSON.stringify(res.headers)}`);
  
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  
  res.on('end', () => {
    console.log('Response:', data);
  });
});

req.on('error', (e) => {
  console.error(`Error: ${e.message}`);
});

req.write(postData);
req.end();
