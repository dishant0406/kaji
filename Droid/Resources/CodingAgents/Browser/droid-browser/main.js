const droidTools = require('./droid-tools');
const playwrightToolCache = require('./playwright-tool-cache');
const { MessageFramer, writeMessage } = require('./framing');
const { PlaywrightClient } = require('./playwright-client');
const { isAllowed } = require('./safety');

function main() {
  const provider = new PlaywrightClient();
  new MessageFramer(process.stdin, message => {
    handle(message, provider).catch(error => sendError(message && message.id, error));
  });
}

async function handle(message, provider) {
  if (!message || typeof message !== 'object') return;
  if (message.method === 'notifications/initialized') return;
  if (message.id === undefined) return;
  send(message.id, await dispatch(message.method, message.params || {}, provider));
}

async function dispatch(method, params, provider) {
  if (method === 'initialize') {
    return {
      protocolVersion: '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'droid-browser', version: '0.3.0' }
    };
  }
  if (method === 'tools/list') return { tools: [...droidTools.tools, ...playwrightToolCache.tools()] };
  if (method === 'tools/call') return callTool(params, provider);
  return {};
}

async function callTool(params, provider) {
  const name = params.name || '';
  const args = params.arguments || {};
  const local = await droidTools.call(name, args, provider);
  if (local) return local;
  if (!name.startsWith('browser_')) throw new Error(`Unknown tool: ${name}`);
  if (!isAllowed(name)) throw new Error(`Tool is disabled by Droid browser safety settings: ${name}`);
  return provider.callTool(name, args);
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
