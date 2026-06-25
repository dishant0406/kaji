const kajiTools = require('./kaji-tools');
const { MessageFramer, writeMessage } = require('./framing');

function main() {
  new MessageFramer(process.stdin, message => {
    handle(message).catch(error => sendError(message && message.id, error));
  });
}

async function handle(message) {
  if (!message || typeof message !== 'object') return;
  if (message.method === 'notifications/initialized') return;
  if (message.id === undefined) return;
  send(message.id, await dispatch(message.method, message.params || {}));
}

async function dispatch(method, params) {
  if (method === 'initialize') {
    return {
      protocolVersion: '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'kaji-browser', version: '1.0.0' }
    };
  }
  if (method === 'tools/list') return { tools: kajiTools.tools };
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

function send(id, result) {
  writeMessage(process.stdout, { jsonrpc: '2.0', id, result });
}

function sendError(id, error) {
  writeMessage(process.stdout, {
    jsonrpc: '2.0',
    id,
    error: { code: -32000, message: error && error.message ? error.message : String(error) }
  });
}

module.exports = { main };
