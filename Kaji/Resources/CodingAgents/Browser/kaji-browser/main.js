const kajiTools = require('./kaji-tools');
const { browserAccessibility } = require('./availability');
const { MessageFramer, writeMessage } = require('./framing');

function main() {
  new MessageFramer(process.stdin, message => {
    handle(message).catch(error => sendError(message && message.id, error));
  });
}

async function handle(message) {
  if (!message || typeof message !== 'object') return;
  if (message.method === 'notifications/initialized') {
    startToolListWatcher();
    return;
  }
  if (message.id === undefined) return;
  send(message.id, await dispatch(message.method, message.params || {}));
}

async function dispatch(method, params) {
  if (method === 'initialize') {
    return {
      protocolVersion: '2025-06-18',
      capabilities: { tools: { listChanged: true } },
      serverInfo: { name: 'kaji-browser', version: '1.0.0' }
    };
  }
  if (method === 'tools/list') return { tools: await kajiTools.list() };
  if (method === 'tools/call') return callTool(params);
  return {};
}

async function callTool(params) {
  const name = params.name || '';
  const args = params.arguments || {};
  const local = await kajiTools.call(name, args);
  if (local) return local;
  throw new Error(`Unknown tool: ${name}`);
}

let toolListWatcher = null;
let lastToolListState = null;

function startToolListWatcher() {
  if (toolListWatcher) return;
  updateToolListState(false).catch(() => {});
  toolListWatcher = setInterval(() => {
    updateToolListState(true).catch(() => {});
  }, 1500);
}

async function updateToolListState(notify) {
  const status = await browserAccessibility();
  const state = status.accessible ? 'accessible' : 'unavailable';
  if (lastToolListState === null) {
    lastToolListState = state;
    return;
  }
  if (lastToolListState === state) return;
  lastToolListState = state;
  if (notify) sendNotification('notifications/tools/list_changed');
}

function send(id, result) {
  writeMessage(process.stdout, { jsonrpc: '2.0', id, result });
}

function sendNotification(method) {
  writeMessage(process.stdout, { jsonrpc: '2.0', method });
}

function sendError(id, error) {
  writeMessage(process.stdout, {
    jsonrpc: '2.0',
    id,
    error: { code: -32000, message: error && error.message ? error.message : String(error) }
  });
}

module.exports = { dispatch, main };
