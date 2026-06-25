const { browserStates, sessionPath } = require('./session');

async function browserAccessibility(timeoutMs = 450) {
  const states = browserStates();
  if (states.length === 0) return unavailable('session_missing', 'Kaji Browser is not reachable. Open the Kaji Browser panel first.');
  const errors = [];
  for (const state of states) {
    const result = await checkState(state, timeoutMs);
    if (result.accessible) return result;
    errors.push(result);
  }
  return {
    accessible: false,
    connected: false,
    reason: 'kaji_not_reachable',
    message: 'Kaji Browser is not reachable. Skip browser actions unless the user opens Kaji Browser.',
    sessionPath: sessionPath(),
    errors
  };
}

async function checkState(state, timeoutMs) {
  try {
    const response = await fetchWithTimeout(`${state.brokerUrl}/status`, timeoutMs);
    if (!response.ok) return unavailable('broker_status_failed', `Kaji Browser broker returned ${response.status}.`, state);
    const body = await response.json();
    return {
      ...body,
      accessible: body.connected !== false,
      reason: body.connected === false ? 'broker_disconnected' : null,
      message: body.connected === false ? 'Kaji Browser broker is not connected.' : null,
      brokerSource: state.source,
      sessionPath: sessionPath()
    };
  } catch (error) {
    return unavailable('broker_unreachable', error && error.message ? error.message : String(error), state);
  }
}

async function fetchWithTimeout(url, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function unavailable(reason, message, state) {
  return {
    accessible: false,
    connected: false,
    reason,
    message,
    brokerUrl: state ? state.brokerUrl : '',
    brokerSource: state ? state.source : 'none',
    sessionPath: sessionPath()
  };
}

module.exports = { browserAccessibility };
