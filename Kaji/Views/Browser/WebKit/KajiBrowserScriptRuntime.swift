import Foundation

enum KajiBrowserScriptRuntime {
    static func wrap(_ body: String) -> String {
        """
        (() => {
          const fail = error => ({ ok: false, error });
          const ok = value => Object.assign({ ok: true }, value || {});
          const find = (target, selector) => {
            const state = window.__kajiBrowserState || {};
            const key = target || selector || '';
            const css = selector || (state.snapshotSelectors && state.snapshotSelectors[key]) || key;
            try { return css ? document.querySelector(css) : null; } catch { return null; }
          };
          const center = el => {
            el.scrollIntoView({ block: 'center', inline: 'center' });
            const rect = el.getBoundingClientRect();
            return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
          };
          const fire = (el, type, point, button) => {
            const init = {
              bubbles: true,
              cancelable: true,
              view: window,
              button,
              buttons: button === 0 ? 1 : 0,
              clientX: point.x,
              clientY: point.y
            };
            try {
              el.dispatchEvent(new PointerEvent(type, init));
            } catch {
              el.dispatchEvent(new MouseEvent(type, init));
            }
          };
          const emitInput = el => {
            try {
              el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
            } catch {
              el.dispatchEvent(new Event('input', { bubbles: true }));
            }
            el.dispatchEvent(new Event('change', { bubbles: true }));
          };
          const nativeValue = (el, value) => {
            const proto = el instanceof HTMLTextAreaElement
              ? HTMLTextAreaElement.prototype
              : el instanceof HTMLInputElement ? HTMLInputElement.prototype : null;
            const descriptor = proto && Object.getOwnPropertyDescriptor(proto, 'value');
            descriptor && descriptor.set ? descriptor.set.call(el, value) : (el.value = value);
          };
          const setText = (el, text, append) => {
            el.focus && el.focus({ preventScroll: true });
            if (el.isContentEditable) {
              if (!append) el.textContent = '';
              document.execCommand('insertText', false, text);
              emitInput(el);
              return;
            }
            if (el instanceof HTMLSelectElement) {
              el.value = text;
              emitInput(el);
              return;
            }
            if ('value' in el) {
              nativeValue(el, append ? `${el.value || ''}${text}` : text);
              emitInput(el);
              return;
            }
            el.textContent = append ? `${el.textContent || ''}${text}` : text;
            emitInput(el);
          };
          const parseKey = value => {
            const parts = String(value).split('+');
            const key = parts.pop();
            return {
              key,
              code: key.length === 1 ? `Key${key.toUpperCase()}` : key,
              meta: parts.includes('Meta') || parts.includes('Command'),
              ctrl: parts.includes('Control') || parts.includes('Ctrl'),
              alt: parts.includes('Alt') || parts.includes('Option'),
              shift: parts.includes('Shift')
            };
          };
          \(body)
        })()
        """
    }
}
