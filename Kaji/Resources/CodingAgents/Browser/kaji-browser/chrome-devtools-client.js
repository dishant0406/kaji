const { browserState } = require('./session');
const { ensureBrokerSessionReady, waitForCdpEndpoint } = require('./broker-session');
const { MCPStdioClient } = require('./mcp-stdio-client');
const chromeDevToolsTools = require('./chrome-devtools-tools');

class ChromeDevToolsClient {
  constructor() {
    this.client = new MCPStdioClient('Chrome DevTools MCP');
    this.providerTools = new Map();
  }

  status() {
    const state = browserState();
    return {
      provider: 'chrome-devtools',
      package: packageSpec(),
      running: this.client.running,
      cdpUrl: state.cdpUrl,
      hasCdp: Boolean(state.cdpUrl),
      startedAt: this.client.startedAt,
      allowlistedToolCount: chromeDevToolsTools.tools.length,
      providerToolCount: this.providerTools.size,
      unsupportedToolsHidden: unsupportedToolsHidden(),
      lastError: this.client.lastError()
    };
  }

  async callTool(name, args) {
    await ensureBrokerSessionReady();
    await this.ensureStarted();
    const request = this.translate(name, args || {});
    if (!request) throw new Error(`Chrome DevTools MCP tool is not allowlisted for Kaji Chromium: ${name}`);
    if (!this.providerTools.has(request.name)) throw new Error(`Chrome DevTools MCP tool is unavailable for Kaji Chromium: ${request.name}`);
    try {
      return await this.client.request('tools/call', { name: request.name, arguments: request.arguments }, timeoutMs());
    } catch (error) {
      throw new Error(`Chrome DevTools MCP failed for ${name}: ${error.message || String(error)}`);
    }
  }

  tools() {
    return chromeDevToolsTools.tools;
  }

  async ensureStarted() {
    if (this.client.running) return;
    const endpoint = await waitForCdpEndpoint();
    this.start(endpoint);
    await this.client.initialize(timeoutMs());
    const result = await this.client.request('tools/list', {}, timeoutMs());
    this.providerTools = new Map((result.tools || []).map(item => [item.name, item]));
  }

  start(endpoint) {
    const args = ['-y', packageSpec(), `--browser-url=${endpoint}`, '--no-usage-statistics'];
    if (enableVision()) args.push('--experimental-vision');
    if (enablePageRouting()) args.push('--experimentalPageIdRouting');
    for (const item of extraArgs()) args.push(item);
    this.client.start('npx', args, childEnvironment());
  }

  translate(name, args) {
    const providerName = chromeDevToolsTools.providerToolName(name);
    if (!providerName) return null;
    if (name === 'browser_navigate') return { name: providerName, arguments: { type: 'url', url: args.url } };
    if (name === 'browser_reload') return { name: providerName, arguments: { type: 'reload' } };
    if (providerName === 'navigate_page_history') return { name: 'navigate_page', arguments: historyArgs(name) };
    if (providerName === 'tabs') return translateTabs(args);
    if (name === 'browser_click') return translateClick(args);
    if (name === 'browser_drag') return { name: providerName, arguments: renameKeys(args, { startTarget: 'from_uid', endTarget: 'to_uid' }) };
    if (name === 'browser_hover') return { name: providerName, arguments: uidArgs(args) };
    if (name === 'browser_type') return { name: providerName, arguments: translateType(args) };
    if (name === 'browser_evaluate') return { name: providerName, arguments: translateEvaluate(args) };
    if (name === 'browser_handle_dialog') return { name: providerName, arguments: translateDialog(args) };
    if (name === 'browser_fill_form') return { name: providerName, arguments: translateForm(args) };
    if (name === 'browser_network_request') return { name: providerName, arguments: translateNetworkRequest(args) };
    if (name === 'browser_take_screenshot') return { name: providerName, arguments: translateScreenshot(args) };
    if (name === 'browser_snapshot') return { name: providerName, arguments: translateSnapshot(args) };
    if (name === 'browser_wait_for') return { name: providerName, arguments: translateWait(args) };
    return { name: providerName, arguments: { ...args } };
  }
}

function translateTabs(args) {
  const action = args.action || 'list';
  if (action === 'list') return { name: 'list_pages', arguments: {} };
  if (action === 'new') return { name: 'new_page', arguments: { url: args.url || 'about:blank' } };
  if (action === 'select') return { name: 'select_page', arguments: { pageId: args.index } };
  if (action === 'close') return { name: 'close_page', arguments: { pageId: args.index } };
  throw new Error(`Unsupported browser_tabs action for Chrome DevTools MCP: ${action}`);
}

function historyArgs(name) {
  return { type: name === 'browser_navigate_back' ? 'back' : 'forward' };
}

function translateClick(args) {
  if (Number.isFinite(args.x) && Number.isFinite(args.y)) return { name: 'click_at', arguments: renameKeys(pick(args, ['x', 'y', 'doubleClick']), { doubleClick: 'dblClick' }) };
  return { name: 'click', arguments: renameKeys(uidArgs(args), { doubleClick: 'dblClick' }) };
}

function translateType(args) {
  return pick(args, ['text']);
}

function translateEvaluate(args) {
  const expression = args.function || args.expression || '';
  const next = { ...args, function: expression };
  delete next.expression;
  return next;
}

function translateNetworkRequest(args) {
  const next = { ...args };
  if (next.number !== undefined && next.reqid === undefined) next.reqid = next.number;
  delete next.number;
  delete next.part;
  return next;
}

function translateDialog(args) {
  return {
    action: args.accept ? 'accept' : 'dismiss',
    ...(args.promptText === undefined ? {} : { promptText: args.promptText })
  };
}

function translateForm(args) {
  return {
    elements: (args.fields || []).map(field => ({
      uid: field.target,
      value: String(field.value ?? '')
    }))
  };
}

function translateScreenshot(args) {
  const next = {};
  if (args.type) next.format = args.type;
  if (args.fullPage !== undefined) next.fullPage = args.fullPage;
  if (args.filename) next.filePath = args.filename;
  if (args.target) next.uid = args.target;
  return next;
}

function translateSnapshot(args) {
  const next = {};
  if (args.filename) next.filePath = args.filename;
  if (args.depth !== undefined || args.boxes !== undefined) next.verbose = true;
  return next;
}

function translateWait(args) {
  const next = {};
  if (args.text) next.text = [args.text];
  if (args.time !== undefined) next.timeout = Math.max(0, Math.round(args.time * 1000));
  if (args.textGone) throw new Error('Chrome DevTools MCP does not support waiting for text to disappear in Kaji allowlisted mode.');
  if (!next.text) throw new Error('Chrome DevTools MCP wait_for requires text in Kaji allowlisted mode.');
  return next;
}

function uidArgs(args) {
  const uid = args.target || args.uid;
  const next = uid ? { uid } : {};
  if (args.doubleClick !== undefined) next.doubleClick = args.doubleClick;
  return next;
}

function renameKeys(args, names) {
  const next = { ...args };
  for (const [from, to] of Object.entries(names)) {
    if (next[from] !== undefined) {
      next[to] = next[from];
      delete next[from];
    }
  }
  return next;
}

function pick(args, keys) {
  const out = {};
  for (const key of keys) {
    if (args[key] !== undefined) out[key] = args[key];
  }
  return out;
}

function packageSpec() { return process.env.KAJI_BROWSER_CHROME_DEVTOOLS_PACKAGE || 'chrome-devtools-mcp@latest'; }
function timeoutMs() { return Number(process.env.KAJI_BROWSER_CHROME_DEVTOOLS_TIMEOUT_MS || 30000); }
function extraArgs() { return (process.env.KAJI_BROWSER_CHROME_DEVTOOLS_ARGS || '').split(/\s+/).filter(Boolean); }
function enableVision() { return process.env.KAJI_BROWSER_CHROME_DEVTOOLS_VISION !== '0'; }
function enablePageRouting() { return process.env.KAJI_BROWSER_CHROME_DEVTOOLS_PAGE_ROUTING !== '0'; }
function unsupportedToolsHidden() { return process.env.KAJI_BROWSER_ALLOW_UNVERIFIED_CDP_TOOLS !== '1'; }

function childEnvironment() {
  return { ...process.env };
}

module.exports = { ChromeDevToolsClient };
