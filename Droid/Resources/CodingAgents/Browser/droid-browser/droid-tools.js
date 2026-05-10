const { imageResult, textResult, tool } = require('./results');
const { browserState, readSession } = require('./session');

const tools = [
  tool('droid_browser_status', 'Return Droid embedded browser broker and CDP status.'),
  tool('droid_browser_session', 'Return the Droid browser session values known to this MCP wrapper.'),
  tool('droid_browser_provider_status', 'Return Playwright MCP provider status for Droid browser automation.'),
  tool('droid_browser_current', 'Return the active Droid browser tab and tab list.'),
  tool('droid_browser_navigate', 'Navigate the active Droid browser tab through Droid broker.', { url: stringSchema('URL or search query') }, ['url']),
  tool('droid_browser_new_tab', 'Open a new Droid browser tab through Droid broker.', { url: stringSchema('Optional URL or search query') }),
  tool('droid_browser_back', 'Go back in the active Droid browser tab.'),
  tool('droid_browser_forward', 'Go forward in the active Droid browser tab.'),
  tool('droid_browser_reload', 'Reload the active Droid browser tab.'),
  tool('droid_browser_read_page', 'Read text and metadata from the active Droid browser tab.'),
  tool('droid_browser_screenshot', 'Capture a PNG screenshot of the active Droid browser tab.')
];

async function call(name, args, provider) {
  if (name === 'droid_browser_status') return textResult(await readStatus());
  if (name === 'droid_browser_session') return textResult(safeSession());
  if (name === 'droid_browser_provider_status') return textResult(provider.status());
  if (name === 'droid_browser_screenshot') return imageResult(await browserAction('screenshot', args));
  const action = actionName(name);
  if (!action) return null;
  return textResult(await browserAction(action, args));
}

function stringSchema(description) {
  return { type: 'string', description };
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

function safeSession() {
  const session = readSession();
  return {
    brokerUrl: process.env.DROID_BROWSER_BROKER_URL || session.brokerUrl || '',
    sessionId: process.env.DROID_BROWSER_SESSION_ID || session.sessionId || '',
    cdpUrl: process.env.DROID_BROWSER_CDP_URL || session.cdpUrl || '',
    cdpPort: process.env.DROID_BROWSER_CDP_PORT || session.cdpPort || '',
    hasToken: Boolean(process.env.DROID_BROWSER_MCP_TOKEN || session.token)
  };
}

async function readStatus() {
  const state = browserState();
  if (!state.brokerUrl) return { connected: false, error: 'Droid browser session is not available. Open Droid Browser first.' };
  const response = await fetch(`${state.brokerUrl}/status`);
  if (!response.ok) return { connected: false, error: `Broker returned ${response.status}` };
  return response.json();
}

async function browserAction(action, args) {
  const state = browserState();
  if (!state.brokerUrl) return { connected: false, error: 'Droid browser session is not available. Open Droid Browser first.' };
  const response = await fetch(`${state.brokerUrl}/browser`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId: state.sessionId, action, arguments: args })
  });
  return parseResponse(response);
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

module.exports = { call, tools };
