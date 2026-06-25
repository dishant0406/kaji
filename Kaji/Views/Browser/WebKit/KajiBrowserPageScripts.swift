import Foundation

enum KajiBrowserPageScripts {
    static let eventBridge = """
    (() => {
      if (window.__kajiBrowserInstalled) return;
      window.__kajiBrowserInstalled = true;
      const bounded = (list, item, max = 500) => {
        list.push(Object.assign({ time: new Date().toISOString() }, item));
        if (list.length > max) list.splice(0, list.length - max);
      };
      window.__kajiBrowserState = { dialogs: [], errors: [], console: [], network: [], snapshotSelectors: {} };
      for (const level of ['debug', 'log', 'info', 'warn', 'error']) {
        const original = console[level] && console[level].bind(console);
        if (!original) continue;
        console[level] = (...args) => {
          bounded(window.__kajiBrowserState.console, {
            level: level === 'warn' ? 'warning' : level,
            text: args.map(value => {
              try { return typeof value === 'string' ? value : JSON.stringify(value); } catch { return String(value); }
            }).join(' ')
          });
          original(...args);
        };
      }
      window.addEventListener('error', event => {
        bounded(window.__kajiBrowserState.errors, {
          message: String(event.message || ''),
          source: String(event.filename || ''),
          line: event.lineno || 0
        });
      });
      window.addEventListener('unhandledrejection', event => {
        bounded(window.__kajiBrowserState.errors, {
          message: String(event.reason && event.reason.message || event.reason || '')
        });
      });
      const originalFetch = window.fetch && window.fetch.bind(window);
      if (originalFetch) {
        window.fetch = async (...args) => {
          const startedAt = performance.now();
          const url = String(args[0] && args[0].url || args[0] || '');
          const method = String(args[1] && args[1].method || args[0] && args[0].method || 'GET');
          try {
            const response = await originalFetch(...args);
            bounded(window.__kajiBrowserState.network, {
              number: window.__kajiBrowserState.network.length + 1,
              type: 'fetch',
              method,
              url,
              status: response.status,
              durationMs: Math.round(performance.now() - startedAt)
            });
            return response;
          } catch (error) {
            bounded(window.__kajiBrowserState.network, {
              number: window.__kajiBrowserState.network.length + 1,
              type: 'fetch',
              method,
              url,
              error: String(error && error.message || error)
            });
            throw error;
          }
        };
      }
      const open = XMLHttpRequest.prototype.open;
      const send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__kajiRequest = { method: String(method || 'GET'), url: String(url || ''), startedAt: performance.now() };
        return open.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('loadend', () => {
          const request = this.__kajiRequest || {};
          bounded(window.__kajiBrowserState.network, {
            number: window.__kajiBrowserState.network.length + 1,
            type: 'xhr',
            method: request.method || 'GET',
            url: request.url || '',
            status: this.status,
            durationMs: Math.round(performance.now() - (request.startedAt || performance.now()))
          });
        });
        return send.apply(this, arguments);
      };
    })();
    """

    static let readableText = """
    (() => {
      const title = document.title || '';
      const url = location.href || '';
      const text = (document.body && (document.body.innerText || document.body.textContent)) || '';
      return `Title: ${title}\nURL: ${url}\n\n${text}`;
    })()
    """

    static let snapshot = """
    (() => {
      const visible = el => {
        const style = getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0
          && style.visibility !== 'hidden'
          && style.display !== 'none'
          && Number(style.opacity || 1) > 0.01;
      };
      const cssPath = el => {
        if (!el || el.nodeType !== 1) return '';
        if (el.id) return '#' + CSS.escape(el.id);
        const parts = [];
        while (el && el.nodeType === 1 && parts.length < 6) {
          let part = el.tagName.toLowerCase();
          if (el.className && typeof el.className === 'string') {
            const name = el.className.trim().split(/\\s+/)[0];
            if (name) part += '.' + CSS.escape(name);
          }
          const parent = el.parentElement;
          if (parent) {
            const same = Array.from(parent.children).filter(x => x.tagName === el.tagName);
            if (same.length > 1) part += `:nth-of-type(${same.indexOf(el) + 1})`;
          }
          parts.unshift(part);
          el = parent;
        }
        return parts.join(' > ');
      };
      const query = 'a,button,input,textarea,select,[role],summary,[contenteditable="true"]';
      const nodes = Array.from(document.querySelectorAll(query)).filter(visible).slice(0, 200);
      return {
        url: location.href,
        title: document.title,
        elements: nodes.map((el, i) => ({
          ref: `e${i + 1}`,
          selector: cssPath(el),
          tag: el.tagName.toLowerCase(),
          role: el.getAttribute('role') || '',
          text: (
            el.innerText || el.value || el.getAttribute('aria-label') || el.getAttribute('title') || ''
          ).trim().slice(0, 160)
        }))
      };
    })()
    """
}
