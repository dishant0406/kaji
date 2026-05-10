#!/usr/bin/env node
const brokerUrl = process.env.DROID_BROWSER_BROKER_URL || '';
const token = process.env.DROID_BROWSER_MCP_TOKEN || '';
const sessionId = process.env.DROID_BROWSER_SESSION_ID || 'default';
let buffer = Buffer.alloc(0);

const tools = [
  tool('droid_browser_status', 'Return Droid embedded browser broker and CDP status.', {}),
  tool('droid_browser_current', 'Return the active Droid browser tab and tab list.', {}),
  tool('droid_browser_navigate', 'Navigate the active Droid browser tab.', { url: stringSchema('URL or search query') }, ['url']),
  tool('droid_browser_new_tab', 'Open a new Droid browser tab.', { url: stringSchema('Optional URL or search query') }),
  tool('droid_browser_back', 'Go back in the active Droid browser tab.', {}),
  tool('droid_browser_forward', 'Go forward in the active Droid browser tab.', {}),
  tool('droid_browser_reload', 'Reload the active Droid browser tab.', {}),
  tool('droid_browser_read_page', 'Read trustworthy text and metadata from the active Droid browser tab.', {}),
  tool('droid_browser_screenshot', 'Capture a PNG screenshot of the active Droid browser tab.', {})
];

process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  readMessages();
});

function tool(name, description, properties, required = []) {
  return {
    name,
    description,
    inputSchema: { type: 'object', properties, required, additionalProperties: false }
  };
}

function stringSchema(description) {
  return { type: 'string', description };
}

function readMessages() {
  while (buffer.length > 0) {
    if (startsWithHeader()) {
      if (!readContentLengthFrame()) return;
      continue;
    }
    if (!readLineFrame()) return;
  }
}

function startsWithHeader() {
  return buffer.subarray(0, Math.min(buffer.length, 32)).toString('utf8').toLowerCase().startsWith('content-length:');
}

function readContentLengthFrame() {
  const headerEnd = buffer.indexOf('\r\n\r\n');
  if (headerEnd < 0) return false;
  const header = buffer.subarray(0, headerEnd).toString('utf8');
  const match = header.match(/content-length:\s*(\d+)/i);
  if (!match) {
    buffer = Buffer.alloc(0);
    return false;
  }
  const length = Number(match[1]);
  const start = headerEnd + 4;
  if (buffer.length < start + length) return false;
  const body = buffer.subarray(start, start + length).toString('utf8');
  buffer = buffer.subarray(start + length);
  parseMessage(body);
  return true;
}

function readLineFrame() {
  const lineEnd = buffer.indexOf('\n');
  if (lineEnd < 0) return false;
  const line = buffer.subarray(0, lineEnd).toString('utf8').trim();
  buffer = buffer.subarray(lineEnd + 1);
  if (line.length > 0) parseMessage(line);
  return true;
}

function parseMessage(body) {
  handle(JSON.parse(body)).catch(error => sendError(null, error));
}

async function handle(message) {
  if (!message || typeof message !== 'object') return;
  if (message.method === 'notifications/initialized') return;
  if (message.id === undefined) return;
  try {
    send(message.id, await dispatch(message.method, message.params || {}));
  } catch (error) {
    sendError(message.id, error);
  }
}

async function dispatch(method, params) {
  if (method === 'initialize') {
    return {
      protocolVersion: '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'droid-browser', version: '0.2.0' }
    };
  }
  if (method === 'tools/list') return { tools };
  if (method === 'tools/call') return callTool(params);
  return {};
}

async function callTool(params) {
  const name = params.name || '';
  const args = params.arguments || {};
  if (name === 'droid_browser_status') return textResult(await readStatus());
  if (name === 'droid_browser_screenshot') return imageResult(await browserAction('screenshot', args));
  const action = actionName(name);
  if (!action) throw new Error(`Unknown tool: ${name}`);
  return textResult(await browserAction(action, args));
}

function actionName(toolName) {
  return {
    droid_browser_current: 'current',
    droid_browser_navigate: 'navigate',
    droid_browser_new_tab: 'new_tab',
    droid_browser_back: 'back',
    droid_browser_forward: 'forward',
    droid_browser_reload: 'reload',
    droid_browser_read_page: 'read_page',
    droid_browser_screenshot: 'screenshot'
  }[toolName];
}

async function readStatus() {
  if (!brokerUrl) return { connected: false, error: 'DROID_BROWSER_BROKER_URL is not set' };
  const response = await fetch(`${brokerUrl}/status`);
  if (!response.ok) return { connected: false, error: `Broker returned ${response.status}` };
  return response.json();
}

async function browserAction(action, args) {
  if (!brokerUrl) return { connected: false, error: 'DROID_BROWSER_BROKER_URL is not set' };
  const response = await fetch(`${brokerUrl}/browser`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ sessionId, action, arguments: args })
  });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { error: text || `Broker returned ${response.status}` };
  }
  if (!response.ok) body.error = body.error || `Broker returned ${response.status}`;
  return body;
}

function imageResult(value) {
  if (!value || !value.imageBase64) return textResult(value);
  const summary = { ...value };
  delete summary.imageBase64;
  return {
    content: [
      { type: 'text', text: JSON.stringify(summary, null, 2) },
      { type: 'image', data: value.imageBase64, mimeType: value.mimeType || 'image/png' }
    ]
  };
}

function textResult(value) {
  return { content: [{ type: 'text', text: JSON.stringify(value, null, 2) }] };
}

function send(id, result) {
  write({ jsonrpc: '2.0', id, result });
}

function sendError(id, error) {
  write({
    jsonrpc: '2.0',
    id,
    error: { code: -32000, message: error && error.message ? error.message : String(error) }
  });
}

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}
