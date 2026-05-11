const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { MessageFramer, writeMessage } = require('./framing');
const fallback = require('./playwright-tools');
const { filterTools } = require('./safety');

let refreshing = false;

function tools() {
  const cached = readCache();
  if (!cached || isStale(cached.updatedAt)) refresh();
  return filterTools(cached ? cached.tools : fallback.tools);
}

function readCache() {
  try {
    const value = JSON.parse(fs.readFileSync(cachePath(), 'utf8'));
    if (value.package === packageSpec() && Array.isArray(value.tools) && value.tools.length > 0) return value;
  } catch {}
  return null;
}

function refresh() {
  if (refreshing || process.env.KAJI_BROWSER_DISABLE_TOOL_CACHE_REFRESH === '1') return;
  refreshing = true;
  const child = spawn('npx', ['-y', packageSpec(), '--isolated', '--snapshot-mode=none'], {
    stdio: ['pipe', 'pipe', 'ignore'],
    env: { ...process.env, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: process.env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD || '1' }
  });
  let nextId = 1;
  const pending = new Map();
  const timer = setTimeout(() => fail(pending, new Error('Playwright tool cache refresh timed out'), child), 5000);
  child.on('exit', () => fail(pending, new Error('Playwright tool cache refresh exited'), child));
  new MessageFramer(child.stdout, message => receive(message, pending));
  request(child, pending, nextId++, 'initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'kaji-browser-tool-cache', version: '0.1.0' }
  }).then(() => {
    writeMessage(child.stdin, { jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
    return request(child, pending, nextId++, 'tools/list', {});
  }).then(result => writeCache(result.tools || [])).catch(() => {}).finally(() => {
    clearTimeout(timer);
    refreshing = false;
    close(child);
  });
}

function request(child, pending, id, method, params) {
  writeMessage(child.stdin, { jsonrpc: '2.0', id, method, params });
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

function fail(pending, error, child) {
  for (const [id, entry] of pending) {
    pending.delete(id);
    entry.reject(error);
  }
  refreshing = false;
  close(child);
}

function receive(message, pending) {
  if (message.id === undefined) return;
  const entry = pending.get(message.id);
  if (!entry) return;
  pending.delete(message.id);
  if (message.error) entry.reject(new Error(message.error.message || 'Playwright MCP error'));
  else entry.resolve(message.result || {});
}

function writeCache(toolsValue) {
  if (!Array.isArray(toolsValue) || toolsValue.length === 0) return;
  fs.mkdirSync(path.dirname(cachePath()), { recursive: true, mode: 0o700 });
  fs.writeFileSync(cachePath(), JSON.stringify({ package: packageSpec(), updatedAt: new Date().toISOString(), tools: toolsValue }, null, 2), { mode: 0o600 });
}

function close(child) {
  if (!child.killed) child.kill();
}

function cachePath() {
  return path.join(os.homedir(), '.kaji', 'browser', 'playwright-tools-cache.json');
}

function packageSpec() {
  return process.env.KAJI_BROWSER_PLAYWRIGHT_PACKAGE || '@playwright/mcp@latest';
}

function isStale(updatedAt) {
  const value = Date.parse(updatedAt || '');
  if (!Number.isFinite(value)) return true;
  return Date.now() - value > cacheTtlMs();
}

function cacheTtlMs() {
  return Number(process.env.KAJI_BROWSER_PLAYWRIGHT_TOOL_CACHE_TTL_MS || 86400000);
}

module.exports = { tools };
