class MessageFramer {
  constructor(input, onMessage) {
    this.buffer = Buffer.alloc(0);
    this.onMessage = onMessage;
    input.on('data', chunk => this.read(chunk));
    if (typeof input.resume === 'function') input.resume();
  }

  read(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length > 0) {
      if (this.startsWithHeader()) {
        if (!this.readHeaderFrame()) return;
      } else if (!this.readLineFrame()) {
        return;
      }
    }
  }

  startsWithHeader() {
    return this.buffer.subarray(0, Math.min(this.buffer.length, 32)).toString('utf8').toLowerCase().startsWith('content-length:');
  }

  readHeaderFrame() {
    const headerEnd = this.buffer.indexOf('\r\n\r\n');
    if (headerEnd < 0) return false;
    const header = this.buffer.subarray(0, headerEnd).toString('utf8');
    const match = header.match(/content-length:\s*(\d+)/i);
    if (!match) {
      this.buffer = Buffer.alloc(0);
      return false;
    }
    const length = Number(match[1]);
    const start = headerEnd + 4;
    if (this.buffer.length < start + length) return false;
    this.emit(this.buffer.subarray(start, start + length).toString('utf8'));
    this.buffer = this.buffer.subarray(start + length);
    return true;
  }

  readLineFrame() {
    const lineEnd = this.buffer.indexOf('\n');
    if (lineEnd < 0) return false;
    const line = this.buffer.subarray(0, lineEnd).toString('utf8').trim();
    this.buffer = this.buffer.subarray(lineEnd + 1);
    if (line) this.emit(line);
    return true;
  }

  emit(text) {
    this.onMessage(JSON.parse(text));
  }
}

function writeMessage(output, message) {
  output.write(`${JSON.stringify(message)}\n`);
}

module.exports = { MessageFramer, writeMessage };
