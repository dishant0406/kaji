const { normalizeError, toolErrorResult } = require('./browser-errors');
const { browserAccessibility } = require('./availability');
const { imageResult, textResult } = require('./results');
const { availabilityTools, nativeTools } = require('./tool-catalog');
const { browserStates, readSession, sessionPath } = require('./session');
const playwrightTools = require('./playwright-compatible-tools');

const allTools = availabilityTools.concat(nativeTools, playwrightTools.tools);

async function list() {
  return allTools;
}

async function call(name, args) {
  if (name === 'kaji_browser_accessible') return textResult(await browserAccessibility());
  if (name === 'kaji_browser_status') return textResult(await readStatus());
  if (name === 'kaji_browser_session') return textResult(safeSession());
  const action = actionName(name);
  if (!action) return null;
  const result = await browserAction(action, args);
  if (result && result.error) return toolErrorResult(result);
  if (name === 'kaji_browser_screenshot' || name === 'browser_take_screenshot') return imageResult(result);
  return textResult(result);
}

function actionName(toolName) {
  return nativeActionName(toolName) || playwrightTools.actionName(toolName);
}

function nativeActionName(toolName) {
  return {
    kaji_browser_current: 'current',
    kaji_browser_open_panel: 'open_panel',
    kaji_browser_close_panel: 'close_panel',
    kaji_browser_navigate: 'navigate',
    kaji_browser_new_tab: 'new_tab',
    kaji_browser_back: 'back',
    kaji_browser_forward: 'forward',
    kaji_browser_reload: 'reload',
    kaji_browser_close: 'close',
    kaji_browser_tabs: 'tabs',
    kaji_browser_resize: 'resize',
    kaji_browser_read_page: 'read_page',
    kaji_browser_screenshot: 'screenshot',
    kaji_browser_eval: 'eval',
    kaji_browser_snapshot: 'snapshot',
    kaji_browser_click: 'click',
    kaji_browser_hover: 'hover',
    kaji_browser_drag: 'drag',
    kaji_browser_fill: 'fill',
    kaji_browser_fill_form: 'fill_form',
    kaji_browser_type: 'type',
    kaji_browser_press_key: 'press_key',
    kaji_browser_select_option: 'select_option',
    kaji_browser_wait: 'wait',
    kaji_browser_get_text: 'get_text',
    kaji_browser_get_html: 'get_html',
    kaji_browser_storage_get: 'storage_get',
    kaji_browser_console_messages: 'console_messages',
    kaji_browser_network_requests: 'network_requests',
    kaji_browser_network_request: 'network_request',
    kaji_browser_handle_dialog: 'handle_dialog',
    kaji_browser_file_upload: 'file_upload',
    kaji_browser_drop: 'drop'
  }[toolName];
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
  const status = await browserAccessibility();
  if (!status.accessible) return status;
  return withReachableBroker('status', async state => {
    const response = await fetch(`${state.brokerUrl}/status`);
    if (!response.ok) return browserError('broker_status_failed', `Broker returned ${response.status}.`, state);
    return { ...(await response.json()), accessible: true, brokerSource: state.source };
  });
}

async function browserAction(action, args) {
  return withReachableBroker(action, async state => {
    const response = await fetch(`${state.brokerUrl}/browser`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: state.sessionId, action, arguments: args })
    });
    return await awaitReadyResult(await parseResponse(response, state, action), action);
  });
}

async function withReachableBroker(action, body) {
  const states = browserStates().filter(state => state.brokerUrl);
  if (states.length === 0) return browserError('session_missing', 'Kaji Browser MCP session file is missing or empty.');
  const errors = [];
  for (const state of states) {
    try {
      const result = await body(state);
      if (result && result.error === 'browser_panel_not_open' && action !== 'open_panel') return await openPanelAndRetry(action, state, body, result);
      return result;
    } catch (error) {
      errors.push(normalizeError(brokerFetchError(action, state, error)));
    }
  }
  return browserError('broker_unreachable', errors.map(error => error.message).join(' '));
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
  return { ...original, error: 'browser_panel_open_timeout', pending: true };
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
  return browserError('broker_unreachable', `Kaji browser broker request failed for ${action}: ${reason}.`, state, action);
}

async function parseResponse(response, state, action) {
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { error: text || `Broker returned ${response.status}` };
  }
  if (response.status === 401) return browserError('unauthorized', 'Kaji Browser broker rejected the MCP token.', state, action);
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
  return { ...result, connected: false, error: 'page_not_ready', action };
}

function browserError(error, message, state = {}, action = '') {
  return { error, message, brokerUrl: state.brokerUrl || '', brokerSource: state.source || '', sessionPath: sessionPath(), connected: false, accessible: false, action };
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = { call, list };
