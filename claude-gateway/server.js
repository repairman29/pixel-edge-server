#!/usr/bin/env node
/**
 * Claude Gateway — Pixel 8 Pro AI Server  v2.0
 *
 * OpenAI-compatible HTTP inference server backed by Claude Opus 4.6.
 * Runs inside the Debian VM and is reachable via Tailscale from anywhere.
 *
 * Endpoints:
 *   GET  /health                  — liveness probe + mini metrics summary
 *   GET  /metrics                 — Prometheus-format metrics scrape endpoint
 *   GET  /v1/models               — list available models (+ local LLM if configured)
 *   POST /v1/chat/completions     — OpenAI-compatible chat (streaming + non-streaming)
 *   POST /v1/agent                — agentic task; Claude uses shell/file/network/service tools
 *   POST /v1/agent/stream         — same as /v1/agent but streams turn-by-turn via SSE
 *
 * Environment:
 *   ANTHROPIC_API_KEY   — required
 *   CLAUDE_GATEWAY_PORT — default 3456
 *   CLAUDE_MODEL        — default claude-opus-4-6
 *   GATEWAY_API_KEY     — optional; if set, all non-health/metrics endpoints require Bearer auth
 *   RATE_LIMIT_RPM      — requests per minute per IP (default 60, 0 = disabled)
 *   LOCAL_LLM_URL       — optional; proxy haiku/local model requests here
 *                          e.g. http://127.0.0.1:8080/v1/chat/completions (llama-server)
 *                          or   http://127.0.0.1:11434/v1/chat/completions (Ollama)
 */

'use strict';

const http       = require('http');
const https      = require('https');
const { exec }   = require('child_process');
const { promisify } = require('util');
const fs         = require('fs').promises;
const nodePath   = require('path');
const Anthropic  = require('@anthropic-ai/sdk');

const execAsync = promisify(exec);

const PORT          = parseInt(process.env.CLAUDE_GATEWAY_PORT || '3456', 10);
const MODEL         = process.env.CLAUDE_MODEL || 'claude-opus-4-6';
const GATEWAY_KEY   = process.env.GATEWAY_API_KEY || '';
const RATE_LIMIT    = parseInt(process.env.RATE_LIMIT_RPM || '60', 10);
const LOCAL_LLM_URL = process.env.LOCAL_LLM_URL || '';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// ─── metrics ──────────────────────────────────────────────────────────────────

const metrics = {
  requests_total:      0,
  requests_errors:     0,
  active_connections:  0,
  tokens_in:           0,
  tokens_out:          0,
  agent_turns_total:   0,
  local_llm_requests:  0,
  start_time:          Date.now(),
};

function recordTokens(input, output) {
  metrics.tokens_in  += (input  || 0);
  metrics.tokens_out += (output || 0);
}

// ─── rate limiting (sliding window per IP) ────────────────────────────────────

const rateLimitMap = new Map(); // ip -> [timestamp, ...]

function isRateLimited(ip) {
  if (!RATE_LIMIT) return false;
  const now = Date.now();
  let timestamps = (rateLimitMap.get(ip) || []).filter(t => now - t < 60_000);
  if (timestamps.length >= RATE_LIMIT) return true;
  timestamps.push(now);
  rateLimitMap.set(ip, timestamps);
  return false;
}

// Prune stale entries every minute
setInterval(() => {
  const now = Date.now();
  for (const [ip, ts] of rateLimitMap.entries()) {
    if (ts.every(t => now - t >= 60_000)) rateLimitMap.delete(ip);
  }
}, 60_000).unref();

// ─── helpers ──────────────────────────────────────────────────────────────────

function sendJSON(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function sseHeaders(res) {
  res.writeHead(200, {
    'Content-Type':                'text/event-stream',
    'Cache-Control':               'no-cache',
    'Connection':                  'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end',  () => {
      try { resolve(JSON.parse(body || '{}')); }
      catch (e) { reject(new Error('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

let requestCounter = 0;

function log(method, url, extra, reqId) {
  const ts = new Date().toISOString();
  console.log(`[${ts}] [${reqId}] ${method} ${url}${extra ? ' — ' + extra : ''}`);
}

function getClientIP(req) {
  return req.headers['x-forwarded-for']?.split(',')[0].trim()
    || req.socket?.remoteAddress
    || 'unknown';
}

function checkAuth(req) {
  if (!GATEWAY_KEY) return true;
  return (req.headers['authorization'] || '') === `Bearer ${GATEWAY_KEY}`;
}

// ─── /health ──────────────────────────────────────────────────────────────────

function handleHealth(res) {
  sendJSON(res, 200, {
    status:         'ok',
    version:        '2.0',
    model:          MODEL,
    port:           PORT,
    uptime_s:       Math.floor(process.uptime()),
    local_llm:      LOCAL_LLM_URL || null,
    rate_limit_rpm: RATE_LIMIT || null,
    auth_enabled:   !!GATEWAY_KEY,
    timestamp:      new Date().toISOString(),
    metrics: {
      requests_total:    metrics.requests_total,
      requests_errors:   metrics.requests_errors,
      active_connections: metrics.active_connections,
      tokens_in:         metrics.tokens_in,
      tokens_out:        metrics.tokens_out,
      agent_turns_total: metrics.agent_turns_total,
    },
  });
}

// ─── /metrics (Prometheus) ────────────────────────────────────────────────────

function handleMetrics(res) {
  const uptime = (Date.now() - metrics.start_time) / 1000;
  const lines = [
    '# HELP claude_gateway_uptime_seconds How long the gateway has been running',
    '# TYPE claude_gateway_uptime_seconds gauge',
    `claude_gateway_uptime_seconds ${uptime.toFixed(1)}`,
    '',
    '# HELP claude_gateway_requests_total Total HTTP requests received',
    '# TYPE claude_gateway_requests_total counter',
    `claude_gateway_requests_total ${metrics.requests_total}`,
    '',
    '# HELP claude_gateway_requests_errors_total Total request errors',
    '# TYPE claude_gateway_requests_errors_total counter',
    `claude_gateway_requests_errors_total ${metrics.requests_errors}`,
    '',
    '# HELP claude_gateway_active_connections Currently active connections',
    '# TYPE claude_gateway_active_connections gauge',
    `claude_gateway_active_connections ${metrics.active_connections}`,
    '',
    '# HELP claude_gateway_tokens_in_total Total input tokens sent to Claude',
    '# TYPE claude_gateway_tokens_in_total counter',
    `claude_gateway_tokens_in_total ${metrics.tokens_in}`,
    '',
    '# HELP claude_gateway_tokens_out_total Total output tokens received from Claude',
    '# TYPE claude_gateway_tokens_out_total counter',
    `claude_gateway_tokens_out_total ${metrics.tokens_out}`,
    '',
    '# HELP claude_gateway_agent_turns_total Total agent tool-use turns executed',
    '# TYPE claude_gateway_agent_turns_total counter',
    `claude_gateway_agent_turns_total ${metrics.agent_turns_total}`,
    '',
    '# HELP claude_gateway_local_llm_requests_total Requests routed to local LLM',
    '# TYPE claude_gateway_local_llm_requests_total counter',
    `claude_gateway_local_llm_requests_total ${metrics.local_llm_requests}`,
    '',
  ];
  res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4' });
  res.end(lines.join('\n'));
}

// ─── /v1/models ───────────────────────────────────────────────────────────────

function handleModels(res) {
  const data = [
    { id: 'claude-opus-4-6',   object: 'model', created: 1700000000, owned_by: 'anthropic' },
    { id: 'claude-sonnet-4-6', object: 'model', created: 1700000000, owned_by: 'anthropic' },
    { id: 'claude-haiku-4-5',  object: 'model', created: 1700000000, owned_by: 'anthropic' },
  ];
  if (LOCAL_LLM_URL) {
    data.push({ id: 'local', object: 'model', created: 1700000000, owned_by: 'local' });
  }
  sendJSON(res, 200, { object: 'list', data });
}

// ─── local LLM proxy ──────────────────────────────────────────────────────────

function isLocalModel(modelName) {
  if (!LOCAL_LLM_URL) return false;
  return modelName === 'local'
    || modelName?.includes('haiku')
    || modelName?.startsWith('ollama/')
    || modelName?.startsWith('local/');
}

function proxyToLocalLLM(body, res) {
  return new Promise((resolve, reject) => {
    const url     = new URL(LOCAL_LLM_URL);
    const payload = JSON.stringify(body);
    const options = {
      hostname: url.hostname,
      port:     url.port || (url.protocol === 'https:' ? 443 : 80),
      path:     url.pathname + (url.search || ''),
      method:   'POST',
      headers:  {
        'Content-Type':   'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    };
    const lib = url.protocol === 'https:' ? https : http;
    const proxyReq = lib.request(options, proxyRes => {
      res.writeHead(proxyRes.statusCode, {
        'Content-Type':                proxyRes.headers['content-type'] || 'application/json',
        'Access-Control-Allow-Origin': '*',
      });
      proxyRes.pipe(res);
      proxyRes.on('end', resolve);
    });
    proxyReq.on('error', reject);
    proxyReq.write(payload);
    proxyReq.end();
  });
}

// ─── /v1/chat/completions ─────────────────────────────────────────────────────

async function handleChat(req, res) {
  const body = await readBody(req);
  const { messages = [], stream = false, max_tokens = 8192, model } = body;

  if (isLocalModel(model)) {
    metrics.local_llm_requests++;
    return proxyToLocalLLM(body, res);
  }

  const systemMsg = messages.find(m => m.role === 'system');
  const userMsgs  = messages
    .filter(m => m.role !== 'system')
    .map(m => ({ role: m.role, content: m.content }));

  const params = {
    model:     model || MODEL,
    max_tokens,
    thinking:  { type: 'adaptive' },
    messages:  userMsgs,
    ...(systemMsg && { system: systemMsg.content }),
  };

  const msgId = `chatcmpl-${Date.now()}`;

  if (stream) {
    sseHeaders(res);
    let inputTokens = 0, outputTokens = 0;

    const responseStream = client.messages.stream(params);
    for await (const event of responseStream) {
      if (event.type === 'message_start') {
        inputTokens = event.message.usage?.input_tokens || 0;
      }
      if (event.type === 'message_delta') {
        outputTokens = event.usage?.output_tokens || 0;
      }
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        res.write(`data: ${JSON.stringify({
          id: msgId, object: 'chat.completion.chunk', created: Math.floor(Date.now() / 1000),
          model: params.model,
          choices: [{ index: 0, delta: { role: 'assistant', content: event.delta.text }, finish_reason: null }],
        })}\n\n`);
      }
    }

    recordTokens(inputTokens, outputTokens);
    res.write(`data: ${JSON.stringify({
      id: msgId, object: 'chat.completion.chunk', created: Math.floor(Date.now() / 1000),
      model: params.model,
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
      usage: { prompt_tokens: inputTokens, completion_tokens: outputTokens, total_tokens: inputTokens + outputTokens },
    })}\n\n`);
    res.write('data: [DONE]\n\n');
    res.end();

  } else {
    const response = await client.messages.create(params);
    const text = response.content.find(b => b.type === 'text')?.text || '';
    recordTokens(response.usage.input_tokens, response.usage.output_tokens);

    sendJSON(res, 200, {
      id: msgId, object: 'chat.completion', created: Math.floor(Date.now() / 1000),
      model: params.model,
      choices: [{ index: 0, message: { role: 'assistant', content: text }, finish_reason: 'stop' }],
      usage: {
        prompt_tokens:     response.usage.input_tokens,
        completion_tokens: response.usage.output_tokens,
        total_tokens:      response.usage.input_tokens + response.usage.output_tokens,
      },
    });
  }
}

// ─── agent tools ──────────────────────────────────────────────────────────────

const AGENT_TOOLS = [
  {
    name: 'run_shell',
    description: 'Run a bash command in the Debian VM and return stdout/stderr. Use for system inspection, file operations, process management, and network diagnostics.',
    input_schema: {
      type: 'object',
      properties: {
        command: { type: 'string', description: 'The bash command to execute.' },
        timeout: { type: 'number', description: 'Timeout in milliseconds (default 15000, max 60000).' },
      },
      required: ['command'],
    },
  },
  {
    name: 'read_file',
    description: 'Read a file from the VM filesystem. Supports home-relative paths (~/...). Returns the last max_bytes bytes by default for log files.',
    input_schema: {
      type: 'object',
      properties: {
        path:      { type: 'string', description: 'Absolute or home-relative path (e.g. ~/claude-gateway/heartbeat.log).' },
        max_bytes: { type: 'number', description: 'Max bytes to read from the end of the file (default 8192, 0 = full file).' },
      },
      required: ['path'],
    },
  },
  {
    name: 'write_file',
    description: 'Write text content to a file on the VM filesystem. Parent directories are created automatically.',
    input_schema: {
      type: 'object',
      properties: {
        path:    { type: 'string', description: 'Absolute or home-relative path.' },
        content: { type: 'string', description: 'Text content to write.' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'restart_service',
    description: 'Restart a systemd user service (e.g. claude-gateway, openclaw-gateway, llama-server). Use to recover a failed service without manual SSH.',
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Systemd service name without the .service suffix.' },
      },
      required: ['name'],
    },
  },
  {
    name: 'http_fetch',
    description: 'Make an HTTP GET or POST request to any URL reachable from the VM. Useful for health-checking other services on localhost or the LAN.',
    input_schema: {
      type: 'object',
      properties: {
        url:    { type: 'string', description: 'The URL to request.' },
        method: { type: 'string', description: 'HTTP method: GET or POST (default GET).' },
        body:   { type: 'string', description: 'JSON request body for POST (optional).' },
      },
      required: ['url'],
    },
  },
  {
    name: 'check_thermal',
    description: 'Read all /sys/class/thermal zones and return temperatures in °C. Use to check if the Pixel is running hot.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'check_disk',
    description: 'Return disk usage summary (df -h) for the VM.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'list_processes',
    description: 'Return the top 20 CPU-consuming processes.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'check_network',
    description: 'Return open listening ports (ss -tlnp) and network interfaces.',
    input_schema: { type: 'object', properties: {} },
  },
];

function expandPath(p) {
  if (p.startsWith('~/')) {
    const home = process.env.HOME || require('os').homedir();
    return nodePath.join(home, p.slice(2));
  }
  return p;
}

async function executeTool(name, input) {
  try {
    switch (name) {
      case 'run_shell': {
        const timeout = Math.min(input.timeout || 15000, 60000);
        const { stdout, stderr } = await execAsync(input.command, { timeout, shell: '/bin/bash' });
        return `STDOUT:\n${stdout || '(empty)'}\nSTDERR:\n${stderr || '(none)'}`;
      }

      case 'read_file': {
        const filePath = expandPath(input.path);
        const maxBytes = input.max_bytes ?? 8192;
        const stat = await fs.stat(filePath);
        let content;
        if (maxBytes === 0 || stat.size <= maxBytes) {
          content = await fs.readFile(filePath, 'utf8');
        } else {
          // Read from the end (tail semantics)
          const fh  = await fs.open(filePath, 'r');
          const buf = Buffer.alloc(maxBytes);
          await fh.read(buf, 0, maxBytes, stat.size - maxBytes);
          await fh.close();
          content = buf.toString('utf8');
        }
        return `File: ${filePath} (${stat.size} bytes total, showing last ${maxBytes === 0 ? 'all' : maxBytes} bytes)\n\n${content}`;
      }

      case 'write_file': {
        const filePath = expandPath(input.path);
        await fs.mkdir(nodePath.dirname(filePath), { recursive: true });
        await fs.writeFile(filePath, input.content, 'utf8');
        return `Written ${input.content.length} chars to ${filePath}`;
      }

      case 'restart_service': {
        const svc = input.name.replace(/[^a-zA-Z0-9_.-]/g, '');
        const { stdout, stderr } = await execAsync(
          `systemctl --user restart "${svc}.service" 2>&1 && echo "Restarted: ${svc}"`,
          { timeout: 15000 }
        );
        return stdout + (stderr ? `\nSTDERR: ${stderr}` : '');
      }

      case 'http_fetch': {
        const method = (input.method || 'GET').toUpperCase();
        const safeUrl = input.url.replace(/'/g, "'\\''");
        const safeBody = (input.body || '{}').replace(/'/g, "'\\''");
        const curlFlags = method === 'POST'
          ? `-s -X POST -H 'Content-Type: application/json' -d '${safeBody}'`
          : '-s';
        const { stdout, stderr } = await execAsync(
          `curl ${curlFlags} --max-time 10 '${safeUrl}'`,
          { timeout: 12000 }
        );
        return stdout || `Error: ${stderr}`;
      }

      case 'check_thermal': {
        // Uses pure shell arithmetic — no bc dependency
        const { stdout } = await execAsync(
          'for z in /sys/class/thermal/thermal_zone*; do ' +
            'name=$(cat "$z/type" 2>/dev/null); ' +
            'temp=$(cat "$z/temp" 2>/dev/null); ' +
            '[ -z "$temp" ] && continue; ' +
            'int=$(( temp / 1000 )); dec=$(( (temp % 1000) / 100 )); ' +
            'printf "%s: %d.%d°C\\n" "$name" "$int" "$dec"; ' +
          'done',
          { timeout: 5000 }
        );
        return stdout || 'No thermal zones found.';
      }

      case 'check_disk': {
        const { stdout } = await execAsync('df -h', { timeout: 5000 });
        return stdout;
      }

      case 'list_processes': {
        const { stdout } = await execAsync('ps aux --sort=-%cpu | head -21', { timeout: 5000 });
        return stdout;
      }

      case 'check_network': {
        const [ports, ifaces] = await Promise.all([
          execAsync('ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null', { timeout: 5000 }),
          execAsync('ip -br addr 2>/dev/null || ifconfig 2>/dev/null', { timeout: 5000 }),
        ]);
        return `PORTS:\n${ports.stdout}\nINTERFACES:\n${ifaces.stdout}`;
      }

      default:
        return `Unknown tool: ${name}`;
    }
  } catch (err) {
    return `Error executing ${name}: ${err.message}`;
  }
}

const AGENT_SYSTEM =
  'You are an autonomous AI agent running inside a Debian Linux VM on a Google Pixel 8 Pro. ' +
  'You have access to shell commands, file I/O, HTTP fetching, and systemd service management. ' +
  'Investigate and complete the task using your tools. Be concise and precise. ' +
  'When done, summarize what you found or did in a clear final message.';

async function runAgentLoop({ task, system, model, max_turns = 20 }) {
  const agentModel  = model || MODEL;
  const agentSystem = system || AGENT_SYSTEM;
  let messages = [{ role: 'user', content: task }];
  let turns    = 0;
  let finalText = '';

  while (turns < max_turns) {
    turns++;
    metrics.agent_turns_total++;

    const response = await client.messages.create({
      model: agentModel, max_tokens: 8192, thinking: { type: 'adaptive' },
      system: agentSystem, tools: AGENT_TOOLS, messages,
    });

    recordTokens(response.usage?.input_tokens, response.usage?.output_tokens);
    messages.push({ role: 'assistant', content: response.content });

    if (response.stop_reason === 'end_turn') {
      finalText = response.content.find(b => b.type === 'text')?.text || '';
      break;
    }
    if (response.stop_reason !== 'tool_use') break;

    const toolUseBlocks = response.content.filter(b => b.type === 'tool_use');
    const toolResults   = [];
    for (const block of toolUseBlocks) {
      const result = await executeTool(block.name, block.input);
      toolResults.push({ type: 'tool_result', tool_use_id: block.id, content: result });
    }
    messages.push({ role: 'user', content: toolResults });
  }

  return { finalText, turns, model: agentModel };
}

// ─── /v1/agent ────────────────────────────────────────────────────────────────

async function handleAgent(req, res) {
  const body = await readBody(req);
  const { task, system, max_turns, model } = body;

  if (!task) {
    return sendJSON(res, 400, { error: { message: '`task` field required', type: 'invalid_request_error' } });
  }

  const { finalText, turns, model: agentModel } = await runAgentLoop({ task, system, model, max_turns });

  sendJSON(res, 200, {
    task, result: finalText, turns,
    model: agentModel, timestamp: new Date().toISOString(),
  });
}

// ─── /v1/agent/stream ─────────────────────────────────────────────────────────

async function handleAgentStream(req, res) {
  const body = await readBody(req);
  const { task, system, max_turns = 20, model } = body;

  if (!task) {
    return sendJSON(res, 400, { error: { message: '`task` field required', type: 'invalid_request_error' } });
  }

  sseHeaders(res);

  function send(type, data) {
    res.write(`data: ${JSON.stringify({ type, ...data })}\n\n`);
  }

  const agentModel  = model || MODEL;
  const agentSystem = system || AGENT_SYSTEM;
  let messages = [{ role: 'user', content: task }];
  let turns    = 0;
  let finalText = '';

  send('start', { task, model: agentModel, timestamp: new Date().toISOString() });

  while (turns < max_turns) {
    turns++;
    metrics.agent_turns_total++;
    send('turn_start', { turn: turns });

    const response = await client.messages.create({
      model: agentModel, max_tokens: 8192, thinking: { type: 'adaptive' },
      system: agentSystem, tools: AGENT_TOOLS, messages,
    });

    recordTokens(response.usage?.input_tokens, response.usage?.output_tokens);
    messages.push({ role: 'assistant', content: response.content });

    for (const block of response.content) {
      if (block.type === 'text' && block.text) {
        send('text', { text: block.text });
      }
      if (block.type === 'tool_use') {
        send('tool_call', { name: block.name, input: block.input });
      }
    }

    if (response.stop_reason === 'end_turn') {
      finalText = response.content.find(b => b.type === 'text')?.text || '';
      break;
    }
    if (response.stop_reason !== 'tool_use') break;

    const toolUseBlocks = response.content.filter(b => b.type === 'tool_use');
    const toolResults   = [];
    for (const block of toolUseBlocks) {
      send('tool_running', { name: block.name });
      const result = await executeTool(block.name, block.input);
      // Truncate result for SSE bandwidth; full result stored in conversation
      send('tool_result', { name: block.name, result: result.slice(0, 2000) });
      toolResults.push({ type: 'tool_result', tool_use_id: block.id, content: result });
    }
    messages.push({ role: 'user', content: toolResults });
  }

  send('done', { result: finalText, turns, model: agentModel, timestamp: new Date().toISOString() });
  res.write('data: [DONE]\n\n');
  res.end();
}

// ─── router ───────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin',  '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  const reqId = String(++requestCounter).padStart(6, '0');
  const ip    = getClientIP(req);
  metrics.requests_total++;
  metrics.active_connections++;
  log(req.method, req.url, `ip=${ip}`, reqId);

  try {
    const { method, url } = req;

    // Always-public endpoints
    if (method === 'GET' && (url === '/health' || url === '/v1/health')) {
      return handleHealth(res);
    }
    if (method === 'GET' && url === '/metrics') {
      return handleMetrics(res);
    }

    // Auth gate
    if (!checkAuth(req)) {
      return sendJSON(res, 401, { error: { message: 'Unauthorized. Set Authorization: Bearer <GATEWAY_API_KEY>.', type: 'auth_error' } });
    }

    // Rate limit gate
    if (isRateLimited(ip)) {
      return sendJSON(res, 429, { error: { message: `Rate limit: ${RATE_LIMIT} req/min per IP`, type: 'rate_limit_error' } });
    }

    if (method === 'GET'  && url === '/v1/models')              return handleModels(res);
    if (method === 'POST' && url === '/v1/chat/completions')    return await handleChat(req, res);
    if (method === 'POST' && url === '/v1/agent')               return await handleAgent(req, res);
    if (method === 'POST' && url === '/v1/agent/stream')        return await handleAgentStream(req, res);

    sendJSON(res, 404, { error: { message: 'Not found', type: 'not_found_error' } });

  } catch (err) {
    metrics.requests_errors++;
    console.error(`[${reqId}] Error:`, err.message);
    if (!res.headersSent) {
      sendJSON(res, 500, { error: { message: err.message, type: 'internal_error' } });
    }
  } finally {
    metrics.active_connections--;
  }
});

// ─── boot ─────────────────────────────────────────────────────────────────────

server.listen(PORT, '0.0.0.0', () => {
  const w = 48;
  console.log('╔' + '═'.repeat(w) + '╗');
  console.log('║' + '   Claude Gateway v2 — Pixel AI Server   '.padEnd(w) + '║');
  console.log('╚' + '═'.repeat(w) + '╝');
  console.log(`  Port       : ${PORT}`);
  console.log(`  Model      : ${MODEL}`);
  console.log(`  Auth       : ${GATEWAY_KEY ? 'enabled (Bearer token)' : 'disabled'}`);
  console.log(`  Rate limit : ${RATE_LIMIT ? RATE_LIMIT + ' req/min per IP' : 'disabled'}`);
  console.log(`  Local LLM  : ${LOCAL_LLM_URL || 'not configured'}`);
  console.log('');
  console.log(`  /health         GET  http://0.0.0.0:${PORT}/health`);
  console.log(`  /metrics        GET  http://0.0.0.0:${PORT}/metrics`);
  console.log(`  /v1/models      GET  http://0.0.0.0:${PORT}/v1/models`);
  console.log(`  /v1/chat        POST http://0.0.0.0:${PORT}/v1/chat/completions`);
  console.log(`  /v1/agent       POST http://0.0.0.0:${PORT}/v1/agent`);
  console.log(`  /v1/agent/stream POST http://0.0.0.0:${PORT}/v1/agent/stream`);
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn('\n  WARNING: ANTHROPIC_API_KEY is not set — requests will fail.\n');
  }
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
process.on('SIGINT',  () => server.close(() => process.exit(0)));
