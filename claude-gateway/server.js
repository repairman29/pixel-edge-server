#!/usr/bin/env node
/**
 * Claude Gateway — Pixel 8 Pro AI Server
 *
 * OpenAI-compatible HTTP inference server backed by Claude Opus 4.6.
 * Runs inside the Debian VM and is reachable via Tailscale from anywhere.
 *
 * Endpoints:
 *   GET  /health                  — liveness probe
 *   GET  /v1/models               — list available models
 *   POST /v1/chat/completions     — OpenAI-compatible chat (streaming + non-streaming)
 *   POST /v1/agent                — submit an agentic task; Claude uses shell + sensor tools
 *
 * Environment:
 *   ANTHROPIC_API_KEY  — required
 *   CLAUDE_GATEWAY_PORT — default 3456
 *   CLAUDE_MODEL        — default claude-opus-4-6
 */

'use strict';

const http = require('http');
const { exec } = require('child_process');
const { promisify } = require('util');
const Anthropic = require('@anthropic-ai/sdk');

const execAsync = promisify(exec);

const PORT   = parseInt(process.env.CLAUDE_GATEWAY_PORT || '3456', 10);
const MODEL  = process.env.CLAUDE_MODEL || 'claude-opus-4-6';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// ─── helpers ──────────────────────────────────────────────────────────────────

function sendJSON(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function sseHeaders(res) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try { resolve(JSON.parse(body || '{}')); }
      catch (e) { reject(new Error('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

function log(method, url, extra) {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${method} ${url}${extra ? ' — ' + extra : ''}`);
}

// ─── /health ──────────────────────────────────────────────────────────────────

function handleHealth(res) {
  sendJSON(res, 200, {
    status: 'ok',
    model: MODEL,
    port: PORT,
    uptime_s: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
}

// ─── /v1/models ───────────────────────────────────────────────────────────────

function handleModels(res) {
  sendJSON(res, 200, {
    object: 'list',
    data: [
      { id: 'claude-opus-4-6',   object: 'model', created: 1700000000, owned_by: 'anthropic' },
      { id: 'claude-sonnet-4-6', object: 'model', created: 1700000000, owned_by: 'anthropic' },
      { id: 'claude-haiku-4-5',  object: 'model', created: 1700000000, owned_by: 'anthropic' },
    ],
  });
}

// ─── /v1/chat/completions ─────────────────────────────────────────────────────

async function handleChat(req, res) {
  const body = await readBody(req);
  const { messages = [], stream = false, max_tokens = 8192, model } = body;

  // Extract system turn from OpenAI-style messages
  const systemMsg = messages.find(m => m.role === 'system');
  const userMsgs  = messages
    .filter(m => m.role !== 'system')
    .map(m => ({ role: m.role, content: m.content }));

  const params = {
    model: model || MODEL,
    max_tokens,
    thinking: { type: 'adaptive' },
    messages: userMsgs,
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

      if (
        event.type === 'content_block_delta' &&
        event.delta.type === 'text_delta'
      ) {
        const chunk = {
          id: msgId,
          object: 'chat.completion.chunk',
          created: Math.floor(Date.now() / 1000),
          model: params.model,
          choices: [{
            index: 0,
            delta: { role: 'assistant', content: event.delta.text },
            finish_reason: null,
          }],
        };
        res.write(`data: ${JSON.stringify(chunk)}\n\n`);
      }
    }

    // Final chunk with usage
    res.write(`data: ${JSON.stringify({
      id: msgId,
      object: 'chat.completion.chunk',
      created: Math.floor(Date.now() / 1000),
      model: params.model,
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
      usage: {
        prompt_tokens: inputTokens,
        completion_tokens: outputTokens,
        total_tokens: inputTokens + outputTokens,
      },
    })}\n\n`);
    res.write('data: [DONE]\n\n');
    res.end();

  } else {
    const response = await client.messages.create(params);
    const text = response.content.find(b => b.type === 'text')?.text || '';

    sendJSON(res, 200, {
      id: msgId,
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: params.model,
      choices: [{
        index: 0,
        message: { role: 'assistant', content: text },
        finish_reason: 'stop',
      }],
      usage: {
        prompt_tokens: response.usage.input_tokens,
        completion_tokens: response.usage.output_tokens,
        total_tokens: response.usage.input_tokens + response.usage.output_tokens,
      },
    });
  }
}

// ─── /v1/agent — agentic task with built-in Pixel tools ──────────────────────

// Tools Claude can use autonomously against the Pixel's VM
const AGENT_TOOLS = [
  {
    name: 'run_shell',
    description: 'Run a bash command in the Debian VM and return stdout/stderr. Use for system inspection, file operations, process management, network checks, etc.',
    input_schema: {
      type: 'object',
      properties: {
        command:  { type: 'string', description: 'The bash command to execute.' },
        timeout:  { type: 'number', description: 'Timeout in milliseconds (default 15000, max 60000).' },
      },
      required: ['command'],
    },
  },
  {
    name: 'check_thermal',
    description: 'Read all /sys/class/thermal zones and return temperatures in °C. Use to check if the Pixel is overheating.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'check_disk',
    description: 'Return disk usage summary (df -h) for the VM.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'list_processes',
    description: 'Return the top 20 CPU-consuming processes (ps aux --sort=-%cpu).',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'check_network',
    description: 'Return open listening ports (ss -tlnp) and basic network interfaces (ip -br addr).',
    input_schema: { type: 'object', properties: {} },
  },
];

async function executeTool(name, input) {
  try {
    switch (name) {
      case 'run_shell': {
        const timeout = Math.min(input.timeout || 15000, 60000);
        const { stdout, stderr } = await execAsync(input.command, { timeout });
        return `STDOUT:\n${stdout || '(empty)'}\nSTDERR:\n${stderr || '(none)'}`;
      }
      case 'check_thermal': {
        const { stdout } = await execAsync(
          'for z in /sys/class/thermal/thermal_zone*; do name=$(cat "$z/type" 2>/dev/null); temp=$(cat "$z/temp" 2>/dev/null); printf "%s: %.1f°C\\n" "$name" "$(echo "$temp / 1000" | bc -l)"; done',
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

async function handleAgent(req, res) {
  const body = await readBody(req);
  const { task, system, max_turns = 20, model } = body;

  if (!task) {
    return sendJSON(res, 400, { error: { message: '`task` field required', type: 'invalid_request_error' } });
  }

  const agentModel   = model || MODEL;
  const agentSystem  = system ||
    'You are an autonomous AI agent running inside a Debian Linux VM on a Google Pixel 8 Pro. ' +
    'You have access to shell commands and system sensor tools. ' +
    'Investigate and complete the task using your tools. Be concise and precise. ' +
    'When you are done, summarize what you found or did in a clear final message.';

  let messages = [{ role: 'user', content: task }];
  let turns = 0;
  let finalText = '';

  while (turns < max_turns) {
    turns++;

    const response = await client.messages.create({
      model: agentModel,
      max_tokens: 8192,
      thinking: { type: 'adaptive' },
      system: agentSystem,
      tools: AGENT_TOOLS,
      messages,
    });

    messages.push({ role: 'assistant', content: response.content });

    if (response.stop_reason === 'end_turn') {
      finalText = response.content.find(b => b.type === 'text')?.text || '';
      break;
    }

    if (response.stop_reason !== 'tool_use') break;

    // Execute all tool calls
    const toolUseBlocks = response.content.filter(b => b.type === 'tool_use');
    const toolResults = [];

    for (const block of toolUseBlocks) {
      const result = await executeTool(block.name, block.input);
      toolResults.push({
        type: 'tool_result',
        tool_use_id: block.id,
        content: result,
      });
    }

    messages.push({ role: 'user', content: toolResults });
  }

  sendJSON(res, 200, {
    task,
    result: finalText,
    turns,
    model: agentModel,
    timestamp: new Date().toISOString(),
  });
}

// ─── router ───────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  log(req.method, req.url);

  try {
    const { method, url } = req;

    if (method === 'GET' && (url === '/health' || url === '/v1/health')) {
      return handleHealth(res);
    }

    if (method === 'GET' && url === '/v1/models') {
      return handleModels(res);
    }

    if (method === 'POST' && url === '/v1/chat/completions') {
      return await handleChat(req, res);
    }

    if (method === 'POST' && url === '/v1/agent') {
      return await handleAgent(req, res);
    }

    sendJSON(res, 404, { error: { message: 'Not found', type: 'not_found_error' } });

  } catch (err) {
    console.error('Request error:', err.message);
    if (!res.headersSent) {
      sendJSON(res, 500, { error: { message: err.message, type: 'internal_error' } });
    }
  }
});

// ─── boot ─────────────────────────────────────────────────────────────────────

server.listen(PORT, '0.0.0.0', () => {
  console.log('╔══════════════════════════════════════════╗');
  console.log('║      Claude Gateway — Pixel AI Server    ║');
  console.log('╚══════════════════════════════════════════╝');
  console.log(`  Port  : ${PORT}`);
  console.log(`  Model : ${MODEL}`);
  console.log(`  Health: http://0.0.0.0:${PORT}/health`);
  console.log(`  Chat  : POST http://0.0.0.0:${PORT}/v1/chat/completions`);
  console.log(`  Agent : POST http://0.0.0.0:${PORT}/v1/agent`);
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn('\n  ⚠  ANTHROPIC_API_KEY is not set — requests will fail.\n');
  }
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
process.on('SIGINT',  () => server.close(() => process.exit(0)));
