const codeGraphTools = require('./codegraph-tools');
const { MessageFramer, writeMessage } = require('./codegraph-framing');

function main() {
  new MessageFramer(process.stdin, message => {
    handle(message).catch(error => sendError(message && message.id, error));
  });
}

async function handle(message) {
  if (!message || typeof message !== 'object') return;
  if (message.method === 'notifications/initialized') return;
  if (message.id === undefined) return;
  send(message.id, dispatch(message.method, message.params || {}));
}

function dispatch(method, params) {
  if (method === 'initialize') {
    return {
      protocolVersion: '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'kaji-codegraph', version: '1.0.0' }
    };
  }
  if (method === 'tools/list') return { tools: codeGraphTools.list() };
  if (method === 'tools/call') return callTool(params);
  return {};
}

function callTool(params) {
  const name = params.name || '';
  const args = params.arguments || {};
  const local = codeGraphTools.call(name, args);
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

module.exports = { dispatch, main };
