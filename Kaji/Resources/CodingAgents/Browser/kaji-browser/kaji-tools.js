const { imageResult, textResult, tool } = require('./results');
const { browserState, readSession } = require('./session');

const tools = [
  tool('kaji_browser_status', 'Return Kaji embedded browser broker and CDP status.'),
  tool('kaji_browser_session', 'Return the Kaji browser session values known to this MCP wrapper.'),
  tool('kaji_browser_provider_status', 'Return Playwright MCP provider status for Kaji browser automation.'),
  tool('kaji_browser_current', 'Return the active Kaji browser tab and tab list.'),
  tool('kaji_browser_navigate', 'Navigate the active Kaji browser tab through Kaji broker.', { url: stringSchema('URL or search query') }, ['url']),
  tool('kaji_browser_new_tab', 'Open a new Kaji browser tab through Kaji broker.', { url: stringSchema('Optional URL or search query') }),
  tool('kaji_browser_back', 'Go back in the active Kaji browser tab.'),
  tool('kaji_browser_forward', 'Go forward in the active Kaji browser tab.'),
  tool('kaji_browser_reload', 'Reload the active Kaji browser tab.'),
  tool('kaji_browser_read_page', 'Read text and metadata from the active Kaji browser tab.'),
  tool('kaji_browser_screenshot', 'Capture a PNG screenshot of the active Kaji browser tab.')
];

async function call(name, args, provider) {
  if (name === 'kaji_browser_status') return textResult(await readStatus());
  if (name === 'kaji_browser_session') return textResult(safeSession());
  if (name === 'kaji_browser_provider_status') return textResult(provider.status());
  if (name === 'kaji_browser_screenshot') return imageResult(await browserAction('screenshot', args));
  const action = actionName(name);
  if (!action) return null;
  return textResult(await browserAction(action, args));
}

function stringSchema(description) {
  return { type: 'string', description };
}

function actionName(toolName) {
  return {
    kaji_browser_current: 'current',
    kaji_browser_navigate: 'navigate',
    kaji_browser_new_tab: 'new_tab',
    kaji_browser_back: 'back',
    kaji_browser_forward: 'forward',
    kaji_browser_reload: 'reload',
    kaji_browser_read_page: 'read_page',
    kaji_browser_screenshot: 'screenshot'
  }[toolName];
}

function safeSession() {
  const session = readSession();
  return {
    brokerUrl: process.env.KAJI_BROWSER_BROKER_URL || session.brokerUrl || '',
    sessionId: process.env.KAJI_BROWSER_SESSION_ID || session.sessionId || '',
    cdpUrl: process.env.KAJI_BROWSER_CDP_URL || session.cdpUrl || '',
    cdpPort: process.env.KAJI_BROWSER_CDP_PORT || session.cdpPort || '',
    hasToken: Boolean(process.env.KAJI_BROWSER_MCP_TOKEN || session.token)
  };
}

async function readStatus() {
  const state = browserState();
  if (!state.brokerUrl) return { connected: false, error: 'Kaji browser session is not available. Open Kaji Browser first.' };
  const response = await fetch(`${state.brokerUrl}/status`);
  if (!response.ok) return { connected: false, error: `Broker returned ${response.status}` };
  return response.json();
}

async function browserAction(action, args) {
  const state = browserState();
  if (!state.brokerUrl) return { connected: false, error: 'Kaji browser session is not available. Open Kaji Browser first.' };
  const response = await fetch(`${state.brokerUrl}/browser`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId: state.sessionId, action, arguments: args })
  });
  return await awaitReadyResult(await parseResponse(response), action, args);
}

async function parseResponse(response) {
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

async function awaitReadyResult(result, action, args) {
  if (!result || result.connected || result.error || !result.pending) return result;
  for (let attempt = 0; attempt < 20; attempt++) {
    await sleep(150);
    const current = await browserAction('current', {});
    if (current.connected || current.error) return current;
  }
  return { ...result, connected: false, error: `${action} did not attach to the Kaji browser in time` };
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = { call, tools };
