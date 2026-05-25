const { imageResult, textResult, tool } = require('./results');
const { browserState, browserStates, readSession, sessionPath } = require('./session');

const tools = [
  tool('kaji_browser_status', 'Return Kaji embedded browser broker and CDP status.'),
  tool('kaji_browser_session', 'Return the Kaji browser session values known to this MCP wrapper.'),
  tool('kaji_browser_provider_status', 'Return active browser automation provider status for Kaji browser automation.'),
  tool('kaji_browser_open_panel', 'Open the Kaji Browser side panel for the active workspace.'),
  tool('kaji_browser_close_panel', 'Close the Kaji Browser side panel for the active workspace.'),
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
    kaji_browser_open_panel: 'open_panel',
    kaji_browser_close_panel: 'close_panel',
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
  return withReachableBroker('status', async state => {
    const response = await fetch(`${state.brokerUrl}/status`);
    if (!response.ok) return { connected: false, error: `Broker returned ${response.status}` };
    return { ...(await response.json()), brokerSource: state.source };
  });
}

async function browserAction(action, args) {
  return withReachableBroker(action, async state => {
    const response = await fetch(`${state.brokerUrl}/browser`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: state.sessionId, action, arguments: args })
    });
    return await awaitReadyResult(await parseResponse(response), action, args);
  });
}

async function withReachableBroker(action, body) {
  const states = browserStates().filter(state => state.brokerUrl);
  if (states.length === 0) return { connected: false, error: 'Kaji browser session is not available. Open Kaji Browser first.' };
  const errors = [];
  for (const state of states) {
    try {
      const result = await body(state);
      if (result && result.error === 'browser_panel_not_open' && action !== 'open_panel') {
        return await openPanelAndRetry(action, state, body, result);
      }
      return result;
    } catch (error) {
      errors.push(brokerFetchError(action, state, error));
    }
  }
  throw new Error(errors.join(' '));
}

async function openPanelAndRetry(action, state, body, original) {
  await sendPanelAction(state, 'open_panel');
  for (let attempt = 0; attempt < 20; attempt++) {
    await sleep(150);
    const current = await body(state);
    if (!current || current.error === 'browser_panel_not_open' || current.pending) continue;
    if (action === 'current') return current;
    return await body(state);
  }
  return { ...original, pending: true, error: 'browser_panel_open_timeout' };
}

async function sendPanelAction(state, action) {
  await fetch(`${state.brokerUrl}/browser`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId: state.sessionId, action, arguments: {} })
  });
}

function brokerFetchError(action, state, error) {
  const reason = error && error.cause && error.cause.code ? error.cause.code : error.message || String(error);
  return [
    `Kaji browser broker request failed for ${action}: ${reason}.`,
    `brokerUrl=${state.brokerUrl || 'missing'}`,
    `source=${state.source || 'unknown'}`,
    `sessionPath=${sessionPath()}`,
    `sessionFile=${sessionDescription()}`,
    'Open a Kaji Browser pane or restart Kaji so the broker session file is refreshed.'
  ].join(' ');
}

function sessionDescription() {
  const session = readSession();
  if (!session.brokerUrl) return 'missing';
  return `updatedAt=${session.updatedAt || 'unknown'}`;
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
