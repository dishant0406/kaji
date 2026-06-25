import Foundation

enum KajiBrowserDiagnosticScripts {
    static func console(level: String?, all: Bool) -> String {
        let level = KajiBrowserJavaScript.literal(level ?? "")
        return """
        (() => {
          const state = window.__kajiBrowserState || {};
          const requested = \(level);
          const items = (state.console || []).concat((state.errors || []).map(error => ({
            level: 'error',
            text: error.message || '',
            source: error.source || '',
            line: error.line || 0,
            time: error.time || ''
          })));
          const filtered = requested ? items.filter(item => item.level === requested) : items;
          return \(all ? "filtered" : "filtered.slice(-100)");
        })()
        """
    }

    static func network(filter: String?, includeStatic: Bool) -> String {
        let filter = KajiBrowserJavaScript.literal(filter ?? "")
        return """
        (() => {
          const state = window.__kajiBrowserState || {};
          const pattern = \(filter);
          const requests = (state.network || []).filter(item => {
            if (!pattern) return true;
            try { return new RegExp(pattern).test(item.url || ''); } catch { return String(item.url || '').includes(pattern); }
          });
          return {
            coverage: 'webkit-js-observed',
            cdpComplete: false,
            staticIncluded: \(includeStatic ? "true" : "false"),
            requests
          };
        })()
        """
    }

    static func networkRequest(number: Int, part: String?) -> String {
        let part = KajiBrowserJavaScript.literal(part ?? "")
        return """
        (() => {
          const state = window.__kajiBrowserState || {};
          const item = (state.network || []).find(request => request.number === \(number));
          if (!item) return null;
          const requested = \(part);
          return requested && item[requested] !== undefined ? item[requested] : item;
        })()
        """
    }
}
