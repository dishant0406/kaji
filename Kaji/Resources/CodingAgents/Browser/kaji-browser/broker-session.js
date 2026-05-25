const { browserStates } = require('./session');

async function waitForCdpEndpoint() {
  for (let attempt = 0; attempt < 20; attempt++) {
    for (const state of browserStates()) {
      if (state.cdpUrl && await isReady(state.cdpUrl)) return state.cdpUrl;
    }
    await sleep(250);
  }
  throw new Error('Kaji browser CDP endpoint is not available. Open the Kaji browser panel first.');
}

async function ensureBrokerSessionReady() {
  const states = browserStates().filter(state => state.brokerUrl);
  if (states.length === 0) throw new Error('Kaji browser session is not available. Open the Kaji browser panel first.');
  const errors = [];
  for (const state of states) {
    try {
      const response = await fetch(`${state.brokerUrl}/browser`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: state.sessionId, action: 'current', arguments: {} })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error || `Kaji browser broker returned ${response.status}`);
      if (body.error && body.error !== 'browser_panel_not_open') throw new Error(body.error);
      if (body.connected) return;
      await openPanel(state);
      await waitForPanel(state);
      return;
    } catch (error) {
      errors.push(brokerFetchError(state, error));
    }
  }
  throw new Error(errors.join(' '));
}

async function openPanel(state) {
  await fetch(`${state.brokerUrl}/browser`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId: state.sessionId, action: 'open_panel', arguments: {} })
  });
}

async function waitForPanel(state) {
  for (let attempt = 0; attempt < 20; attempt++) {
    await sleep(150);
    const response = await fetch(`${state.brokerUrl}/browser`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: state.sessionId, action: 'current', arguments: {} })
    });
    const body = await response.json().catch(() => ({}));
    if (body.connected) return;
  }
  throw new Error('Kaji browser panel did not open in time.');
}

function brokerFetchError(state, error) {
  const reason = error && error.cause && error.cause.code ? error.cause.code : error.message || String(error);
  return `Kaji browser broker is unreachable at ${state.brokerUrl} (${state.source || 'unknown'}): ${reason}. Open a Kaji Browser pane or restart Kaji so the broker session file is refreshed.`;
}

async function isReady(endpoint) {
  try {
    const response = await fetch(`${endpoint}/json/version`);
    return response.ok;
  } catch {
    return false;
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = { ensureBrokerSessionReady, waitForCdpEndpoint };
