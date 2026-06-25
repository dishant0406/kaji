const { sessionPath } = require('./session');

const recoveries = {
  session_missing: 'Open Kaji with Browser enabled, or click Repair in Kaji Settings > Extensions > Kaji Browser MCP.',
  kaji_not_reachable: 'Open Kaji Browser from the side panel, then retry the same browser tool.',
  broker_unreachable: 'Restart Kaji or close and reopen the Kaji Browser side panel, then retry.',
  broker_status_failed: 'Restart Kaji and retry the same browser tool.',
  broker_disconnected: 'Close and reopen the Kaji Browser side panel, then retry.',
  browser_panel_not_open: 'Call kaji_browser_open_panel, wait briefly, then retry the same browser tool.',
  browser_panel_open_timeout: 'Open Kaji Browser manually from the side panel, then retry.',
  unauthorized: 'Repair the Kaji Browser MCP install from Kaji Settings > Extensions.',
  missing_url: 'Pass a non-empty url argument.',
  missing_key: 'Pass a key argument such as Enter or Meta+A.',
  missing_size: 'Pass positive width and height arguments.',
  missing_tab: 'Pass a valid tab index or tab id.',
  missing_script: 'Pass a script or function argument.',
  selector_not_found: 'Call kaji_browser_snapshot, then retry with a selector or target ref from the snapshot.',
  screenshot_unavailable: 'Wait for the page to finish loading, then retry the screenshot.',
  unknown_action: 'Use one of the listed kaji_browser_* or browser_* tools instead of a raw action.'
};

function toolErrorResult(value, fallbackCode = 'browser_action_failed') {
  return {
    isError: true,
    content: [{ type: 'text', text: JSON.stringify(normalizeError(value, fallbackCode), null, 2) }]
  };
}

function normalizeError(value, fallbackCode = 'browser_action_failed') {
  if (typeof value === 'string') return errorObject(fallbackCode, value);
  const code = value.code || value.error || value.reason || fallbackCode;
  const message = value.message || value.errorMessage || humanMessage(code);
  return {
    code,
    message,
    recovery: value.recovery || recoveries[code] || recoveries[fallbackCode] || 'Retry after checking kaji_browser_status.',
    sessionPath: value.sessionPath || sessionPath(),
    brokerUrl: value.brokerUrl || '',
    brokerSource: value.brokerSource || value.source || '',
    connected: value.connected === true,
    accessible: value.accessible === true,
    action: value.action || '',
    details: value
  };
}

function errorObject(code, message) {
  return {
    code,
    message: message || humanMessage(code),
    recovery: recoveries[code] || 'Retry after checking kaji_browser_status.',
    sessionPath: sessionPath(),
    connected: false,
    accessible: false
  };
}

function humanMessage(code) {
  return String(code).split('_').join(' ');
}

module.exports = { normalizeError, toolErrorResult };
