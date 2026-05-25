const { spawn } = require('child_process');
const { MessageFramer, writeMessage } = require('./framing');

class MCPStdioClient {
  constructor(label) {
    this.label = label;
    this.child = null;
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = '';
    this.startedAt = null;
  }

  get running() {
    return Boolean(this.child);
  }

  lastError() {
    return this.stderr.split('\n').filter(Boolean).slice(-3).join('\n');
  }

  start(command, args, env) {
    this.child = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'], env });
    this.startedAt = new Date().toISOString();
    new MessageFramer(this.child.stdout, message => this.receive(message));
    this.child.stderr.on('data', chunk => { this.stderr += chunk.toString(); });
    this.child.on('exit', () => this.reset(new Error(`${this.label} exited`)));
  }

  async initialize(timeout) {
    await this.request('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'kaji-browser-wrapper', version: '0.1.0' }
    }, timeout);
    this.notify('notifications/initialized', {});
  }

  request(method, params, timeout) {
    const id = this.nextId++;
    writeMessage(this.child.stdin, { jsonrpc: '2.0', id, method, params });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${this.label} request timed out: ${method}`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
    });
  }

  notify(method, params) {
    writeMessage(this.child.stdin, { jsonrpc: '2.0', method, params });
  }

  receive(message) {
    if (message.id === undefined) return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    clearTimeout(pending.timer);
    this.pending.delete(message.id);
    if (message.error) pending.reject(new Error(message.error.message || JSON.stringify(message.error)));
    else pending.resolve(message.result || {});
  }

  reset(error) {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(error);
      this.pending.delete(id);
    }
    this.child = null;
  }
}

module.exports = { MCPStdioClient };
