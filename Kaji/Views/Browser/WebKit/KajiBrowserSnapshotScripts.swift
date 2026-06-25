import Foundation

enum KajiBrowserSnapshotScripts {
    static func snapshot(depth: Int?, boxes: Bool) -> String {
        """
        (() => {
          const limit = 300;
          const maxDepth = \(depth ?? 12);
          const includeBoxes = \(boxes ? "true" : "false");
          const state = window.__kajiBrowserState || (window.__kajiBrowserState = {});
          const visible = el => {
            const style = getComputedStyle(el);
            const rect = el.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0
              && style.visibility !== 'hidden'
              && style.display !== 'none'
              && Number(style.opacity || 1) > 0.01;
          };
          const selector = el => {
            if (!el || el.nodeType !== 1) return '';
            if (el.id) return '#' + CSS.escape(el.id);
            const parts = [];
            while (el && el.nodeType === 1 && parts.length < maxDepth) {
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
          const role = el => {
            const explicit = el.getAttribute('role');
            if (explicit) return explicit;
            const tag = el.tagName.toLowerCase();
            if (tag === 'a') return 'link';
            if (tag === 'button') return 'button';
            if (tag === 'select') return 'combobox';
            if (tag === 'textarea') return 'textbox';
            if (tag === 'input') {
              const type = (el.getAttribute('type') || 'text').toLowerCase();
              if (['button', 'submit', 'reset'].includes(type)) return 'button';
              if (type === 'checkbox') return 'checkbox';
              if (type === 'radio') return 'radio';
              return 'textbox';
            }
            if (el.isContentEditable) return 'textbox';
            return tag;
          };
          const name = el => (
            el.getAttribute('aria-label')
            || el.getAttribute('title')
            || el.getAttribute('placeholder')
            || el.innerText
            || el.value
            || ''
          ).trim().replace(/\\s+/g, ' ').slice(0, 200);
          const query = 'a,button,input,textarea,select,[role],summary,[contenteditable="true"],[onclick]';
          const nodes = Array.from(document.querySelectorAll(query)).filter(visible).slice(0, limit);
          state.snapshotSelectors = {};
          const elements = nodes.map((el, index) => {
            const ref = `e${index + 1}`;
            const css = selector(el);
            state.snapshotSelectors[ref] = css;
            const rect = el.getBoundingClientRect();
            const item = {
              ref,
              selector: css,
              tag: el.tagName.toLowerCase(),
              role: role(el),
              name: name(el),
              text: name(el),
              value: 'value' in el ? String(el.value || '') : '',
              checked: Boolean(el.checked),
              disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true')
            };
            if (includeBoxes) item.bounds = {
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height
            };
            return item;
          });
          return { url: location.href, title: document.title, elements };
        })()
        """
    }
}
