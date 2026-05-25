const { browserState } = require('./session');
const { ensureBrokerSessionReady, waitForCdpEndpoint } = require('./broker-session');
const { MCPStdioClient } = require('./mcp-stdio-client');

class PlaywrightClient {
  constructor() {
    this.client = new MCPStdioClient('Playwright MCP');
  }

  status() {
    const state = browserState();
    return {
      provider: 'playwright',
      package: packageSpec(),
      running: this.client.running,
      cdpUrl: state.cdpUrl,
      hasCdp: Boolean(state.cdpUrl),
      startedAt: this.client.startedAt,
      lastError: this.client.lastError()
    };
  }

  async callTool(name, args) {
    await ensureBrokerSessionReady();
    await this.ensureStarted();
    return this.request('tools/call', { name, arguments: args || {} }, timeoutMs());
  }

  async ensureStarted() {
    if (this.client.running) return;
    const endpoint = await waitForCdpEndpoint();
    this.start(endpoint);
    await this.client.initialize(timeoutMs());
  }

  start(endpoint) {
    const args = ['-y', packageSpec(), `--cdp-endpoint=${endpoint}`, '--output-mode=stdout', '--snapshot-mode=full'];
    for (const item of extraArgs()) args.push(item);
    this.client.start('npx', args, childEnvironment());
  }

  request(method, params, timeout) {
    return this.client.request(method, params, timeout);
  }
}

function packageSpec() { return process.env.KAJI_BROWSER_PLAYWRIGHT_PACKAGE || '@playwright/mcp@latest'; }
function timeoutMs() { return Number(process.env.KAJI_BROWSER_PLAYWRIGHT_TIMEOUT_MS || 30000); }
function extraArgs() { return (process.env.KAJI_BROWSER_PLAYWRIGHT_ARGS || '').split(/\s+/).filter(Boolean); }

function childEnvironment() {
  const env = { ...process.env };
  env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD || '1';
  return env;
}

module.exports = { PlaywrightClient };
