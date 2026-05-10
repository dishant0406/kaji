const { spawn } = require('child_process');
const { MessageFramer, writeMessage } = require('./framing');
const { browserState } = require('./session');

class PlaywrightClient {
  constructor() {
    this.child = null;
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = '';
    this.startedAt = null;
  }

  status() {
    const state = browserState();
    return {
      provider: 'playwright',
      package: packageSpec(),
      running: Boolean(this.child),
      cdpUrl: state.cdpUrl,
      hasCdp: Boolean(state.cdpUrl),
      startedAt: this.startedAt,
      lastError: this.stderr.split('\n').filter(Boolean).slice(-3).join('\n')
    };
  }

  async callTool(name, args) {
    await this.ensureStarted();
    return this.request('tools/call', { name, arguments: args || {} }, timeoutMs());
  }

  async ensureStarted() {
    if (this.child) return;
    const endpoint = await waitForCdpEndpoint();
    this.start(endpoint);
    await this.request('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'droid-browser-wrapper', version: '0.1.0' }
    }, timeoutMs());
    this.notify('notifications/initialized', {});
  }

  start(endpoint) {
    const args = ['-y', packageSpec(), `--cdp-endpoint=${endpoint}`, '--output-mode=stdout', '--snapshot-mode=full'];
    for (const item of extraArgs()) args.push(item);
    this.child = spawn('npx', args, { stdio: ['pipe', 'pipe', 'pipe'], env: childEnvironment() });
    this.startedAt = new Date().toISOString();
    new MessageFramer(this.child.stdout, message => this.receive(message));
    this.child.stderr.on('data', chunk => { this.stderr += chunk.toString(); });
    this.child.on('exit', () => this.reset(new Error('Playwright MCP exited')));
  }

  request(method, params, timeout) {
    const id = this.nextId++;
    writeMessage(this.child.stdin, { jsonrpc: '2.0', id, method, params });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Playwright MCP request timed out: ${method}`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
    });
  }

  notify(method, params) {
    writeMessage(this.child.stdin, { jsonrpc: '2.0', method, params });
  }

  receive(message) {
    if (message.id === undefined) return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    clearTimeout(pending.timer);
    this.pending.delete(message.id);
    if (message.error) pending.reject(new Error(message.error.message || JSON.stringify(message.error)));
    else pending.resolve(message.result || {});
  }

  reset(error) {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(error);
      this.pending.delete(id);
    }
    this.child = null;
  }
}

async function waitForCdpEndpoint() {
  for (let attempt = 0; attempt < 20; attempt++) {
    const state = browserState();
    if (state.cdpUrl && await isReady(state.cdpUrl)) return state.cdpUrl;
    await sleep(250);
  }
  throw new Error('Droid browser CDP endpoint is not available. Open the Droid browser panel first.');
}

async function isReady(endpoint) {
  try {
    const response = await fetch(`${endpoint}/json/version`);
    return response.ok;
  } catch {
    return false;
  }
}

function packageSpec() { return process.env.DROID_BROWSER_PLAYWRIGHT_PACKAGE || '@playwright/mcp@latest'; }
function timeoutMs() { return Number(process.env.DROID_BROWSER_PLAYWRIGHT_TIMEOUT_MS || 30000); }
function extraArgs() { return (process.env.DROID_BROWSER_PLAYWRIGHT_ARGS || '').split(/\s+/).filter(Boolean); }
function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

function childEnvironment() {
  const env = { ...process.env };
  env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD || '1';
  return env;
}

module.exports = { PlaywrightClient };
