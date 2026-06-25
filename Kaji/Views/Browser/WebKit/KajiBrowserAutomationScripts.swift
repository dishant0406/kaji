import Foundation

enum KajiBrowserAutomationScripts {
    static func click(selector: String) -> String {
        let selector = KajiBrowserJavaScript.literal(selector)
        return script("""
        const el = find(
        \(selector)
        );
        if (!el) return fail('not_found');
        center(el);
        el.focus && el.focus({ preventScroll: true });
        fire(el, 'pointerdown');
        fire(el, 'mousedown');
        fire(el, 'pointerup');
        fire(el, 'mouseup');
        fire(el, 'click');
        return ok();
        """)
    }

    static func fill(selector: String, text: String) -> String {
        let selector = KajiBrowserJavaScript.literal(selector)
        let text = KajiBrowserJavaScript.literal(text)
        return script("""
        const el = find(
        \(selector)
        );
        if (!el) return fail('not_found');
        center(el);
        setText(el,
        \(text)
        , false);
        return ok();
        """)
    }

    static func type(selector: String, text: String) -> String {
        let selector = KajiBrowserJavaScript.literal(selector)
        let text = KajiBrowserJavaScript.literal(text)
        return script("""
        const el = find(
        \(selector)
        );
        if (!el) return fail('not_found');
        center(el);
        setText(el,
        \(text)
        , true);
        return ok();
        """)
    }

    static func waitSelector(_ selector: String) -> String {
        let selector = KajiBrowserJavaScript.literal(selector)
        return """
        (() => {
          const el = document.querySelector(\(selector));
          if (!el) return false;
          const style = getComputedStyle(el);
          const rect = el.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';
        })()
        """
    }

    static func getText(selector: String) -> String {
        let selector = KajiBrowserJavaScript.literal(selector)
        return """
        (() => {
          const el = document.querySelector(\(selector));
          return el ? (el.innerText || el.textContent || '') : null;
        })()
        """
    }

    static func getHTML(selector: String) -> String {
        let selector = KajiBrowserJavaScript.literal(selector)
        return """
        (() => {
          const el = document.querySelector(\(selector));
          return el ? el.outerHTML : null;
        })()
        """
    }

    static func storageGet(type: String, key: String?) -> String {
        let type = KajiBrowserJavaScript.literal(type == "session" ? "session" : "local")
        let key = key.map(KajiBrowserJavaScript.literal) ?? "null"
        return """
        (() => {
          const store = \(type) === 'session' ? sessionStorage : localStorage;
          const key = \(key);
          if (key === null) {
            return Object.fromEntries(Array.from(
              { length: store.length },
              (_, i) => [store.key(i), store.getItem(store.key(i))]
            ));
          }
          return store.getItem(String(key));
        })()
        """
    }

    private static func script(_ body: String) -> String {
        """
        (() => {
          const fail = error => ({ ok: false, error });
          const ok = () => ({ ok: true });
          const find = selector => document.querySelector(selector);
          const center = el => el.scrollIntoView({ block: 'center', inline: 'center' });
          const fire = (el, type) => {
            const rect = el.getBoundingClientRect();
            const init = {
              bubbles: true,
              cancelable: true,
              view: window,
              clientX: rect.left + rect.width / 2,
              clientY: rect.top + rect.height / 2
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
            const setter = descriptor && descriptor.set;
            setter ? setter.call(el, value) : (el.value = value);
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
              const next = append ? `${el.value || ''}${text}` : text;
              nativeValue(el, next);
              emitInput(el);
              return;
            }
            el.textContent = append ? `${el.textContent || ''}${text}` : text;
            emitInput(el);
          };
          \(body)
        })()
        """
    }
}
