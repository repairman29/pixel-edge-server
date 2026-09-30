#!/data/data/com.termux/files/usr/bin/node
/**
 * ollama-proxy.js
 * Forwards http://127.0.0.1:11434 → http://127.0.0.1:8889
 * so clawdbot's built-in Ollama provider finds Ragionare.
 */

const http = require('http');

const LISTEN_PORT = 11434;
const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = 8889;

const server = http.createServer((req, res) => {
  const options = {
    hostname: TARGET_HOST,
    port: TARGET_PORT,
    path: req.url,
    method: req.method,
    headers: req.headers,
  };

  const proxy = http.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res, { end: true });
  });

  proxy.on('error', (err) => {
    res.writeHead(502);
    res.end(`Proxy error: ${err.message}`);
  });

  req.pipe(proxy, { end: true });
});

server.listen(LISTEN_PORT, '127.0.0.1', () => {
  console.log(`ollama-proxy: 127.0.0.1:${LISTEN_PORT} → ${TARGET_HOST}:${TARGET_PORT}`);
});
