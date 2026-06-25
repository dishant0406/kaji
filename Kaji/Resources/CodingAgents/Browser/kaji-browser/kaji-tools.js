const { imageResult, textResult, tool } = require('./results');
const { browserStates, readSession, sessionPath } = require('./session');
const playwrightTools = require('./playwright-compatible-tools');

const nativeTools = [
  tool('kaji_browser_status', 'Return Kaji embedded WebKit browser broker status.'),
  tool('kaji_browser_session', 'Return the Kaji WebKit browser session values known to this MCP wrapper.'),
  tool('kaji_browser_open_panel', 'Open the Kaji Browser side panel for the active workspace.'),
  tool('kaji_browser_close_panel', 'Close the Kaji Browser side panel for the active workspace.'),
  tool('kaji_browser_current', 'Return the active Kaji browser tab and tab list.'),
  tool('kaji_browser_navigate', 'Navigate the active Kaji browser tab.', { url: stringSchema('URL or search query') }, ['url']),
  tool('kaji_browser_new_tab', 'Open a new Kaji browser tab.', { url: stringSchema('Optional URL or search query') }),
  tool('kaji_browser_back', 'Go back in the active Kaji browser tab.'),
  tool('kaji_browser_forward', 'Go forward in the active Kaji browser tab.'),
  tool('kaji_browser_reload', 'Reload the active Kaji browser tab.'),
  tool('kaji_browser_read_page', 'Read text and metadata from the active Kaji browser tab.'),
  tool('kaji_browser_screenshot', 'Capture a visible PNG screenshot of the active Kaji browser tab.'),
  tool('kaji_browser_eval', 'Evaluate JavaScript in the active Kaji browser tab.', { script: stringSchema('JavaScript expression or IIFE') }, ['script']),
  tool('kaji_browser_snapshot', 'Return interactive element refs and selectors from the active Kaji browser tab.'),
  tool('kaji_browser_click', 'Click an element by CSS selector.', { selector: stringSchema('CSS selector') }, ['selector']),
  tool('kaji_browser_fill', 'Fill an input, textarea, select-like field, or contenteditable by CSS selector.', { selector: stringSchema('CSS selector'), text: stringSchema('Text to enter') }, ['selector', 'text']),
  tool('kaji_browser_type', 'Type text into a field by CSS selector.', { selector: stringSchema('CSS selector'), text: stringSchema('Text to enter') }, ['selector', 'text']),
  tool('kaji_browser_wait', 'Wait for a visible element by CSS selector.', { selector: stringSchema('CSS selector'), timeoutMs: stringSchema('Optional timeout in milliseconds') }, ['selector']),
  tool('kaji_browser_get_text', 'Read text from an element by CSS selector.', { selector: stringSchema('CSS selector') }, ['selector']),
  tool('kaji_browser_get_html', 'Read outer HTML from an element by CSS selector.', { selector: stringSchema('CSS selector') }, ['selector']),
  tool('kaji_browser_storage_get', 'Read localStorage or sessionStorage.', { type: stringSchema('local or session'), key: stringSchema('Optional storage key') })
];

const tools = nativeTools.concat(playwrightTools.tools);

async function call(name, args) {
  if (name === 'kaji_browser_status') return textResult(await readStatus());
  if (name === 'kaji_browser_session') return textResult(safeSession());
  if (name === 'kaji_browser_screenshot' || name === 'browser_take_screenshot') {
    return imageResult(await browserAction('screenshot', args));
  }
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
    kaji_browser_eval: 'eval',
    kaji_browser_snapshot: 'snapshot',
    kaji_browser_click: 'click',
    kaji_browser_fill: 'fill',
    kaji_browser_type: 'type',
    kaji_browser_wait: 'wait',
    kaji_browser_get_text: 'get_text',
    kaji_browser_get_html: 'get_html',
    kaji_browser_storage_get: 'storage_get'
  }[toolName] || playwrightTools.actionName(toolName);
}

function safeSession() {
  const session = readSession();
  return {
    brokerUrl: process.env.KAJI_BROWSER_BROKER_URL || session.brokerUrl || '',
    sessionId: process.env.KAJI_BROWSER_SESSION_ID || session.sessionId || '',
    engine: 'webkit',
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
    return await awaitReadyResult(await parseResponse(response), action);
  });
}

async function withReachableBroker(action, body) {
  const states = browserStates().filter(state => state.brokerUrl);
  if (states.length === 0) return { connected: false, error: 'Kaji browser session is not available. Open Kaji Browser first.' };
  const errors = [];
  for (const state of states) {
    try {
      const result = await body(state);
      if (result && result.error === 'browser_panel_not_open' && action !== 'open_panel') return await openPanelAndRetry(action, state, body, result);
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
  return [`Kaji browser broker request failed for ${action}: ${reason}.`, `brokerUrl=${state.brokerUrl || 'missing'}`, `source=${state.source || 'unknown'}`, `sessionPath=${sessionPath()}`].join(' ');
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

async function awaitReadyResult(result, action) {
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
