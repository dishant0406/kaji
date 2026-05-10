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
  const session = readSession();
  return {
    brokerUrl: process.env.DROID_BROWSER_BROKER_URL || session.brokerUrl || '',
    token: process.env.DROID_BROWSER_MCP_TOKEN || session.token || '',
    sessionId: process.env.DROID_BROWSER_SESSION_ID || session.sessionId || 'default',
    cdpUrl: process.env.DROID_BROWSER_CDP_URL || session.cdpUrl || '',
    cdpPort: process.env.DROID_BROWSER_CDP_PORT || String(session.cdpPort || '')
  };
}

function sessionPath() {
  return path.join(os.homedir(), '.droid', 'browser', 'session.json');
}

module.exports = { browserState, readSession, sessionPath };
