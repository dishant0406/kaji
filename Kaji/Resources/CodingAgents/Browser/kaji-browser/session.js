const fs = require('fs');
const os = require('os');
const path = require('path');

function readSession() {
  try {
    return JSON.parse(fs.readFileSync(sessionPath(), 'utf8'));
  } catch {
    return {};
  }
}

function browserState() {
  return browserStates()[0] || emptyState();
}

function browserStates() {
  const session = readSession();
  return uniqueStates([environmentState(), sessionState(session)]).filter(state => state.brokerUrl || state.cdpUrl);
}

function environmentState() {
  return {
    brokerUrl: process.env.KAJI_BROWSER_BROKER_URL || '',
    token: process.env.KAJI_BROWSER_MCP_TOKEN || '',
    sessionId: process.env.KAJI_BROWSER_SESSION_ID || 'default',
    cdpUrl: process.env.KAJI_BROWSER_CDP_URL || '',
    cdpPort: process.env.KAJI_BROWSER_CDP_PORT || '',
    source: 'environment'
  };
}

function sessionState(session) {
  return {
    brokerUrl: session.brokerUrl || '',
    token: session.token || '',
    sessionId: session.sessionId || process.env.KAJI_BROWSER_SESSION_ID || 'default',
    cdpUrl: session.cdpUrl || '',
    cdpPort: String(session.cdpPort || ''),
    updatedAt: session.updatedAt || '',
    source: 'session-file'
  };
}

function uniqueStates(states) {
  const seen = new Set();
  const out = [];
  for (const state of states) {
    const key = `${state.brokerUrl}|${state.token}|${state.cdpUrl}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(state);
  }
  return out;
}

function emptyState() {
  return {
    brokerUrl: '',
    token: '',
    sessionId: 'default',
    cdpUrl: '',
    cdpPort: '',
    source: 'empty'
  };
}

function sessionPath() {
  return path.join(os.homedir(), '.kaji', 'browser', 'session.json');
}

module.exports = { browserState, browserStates, readSession, sessionPath };
