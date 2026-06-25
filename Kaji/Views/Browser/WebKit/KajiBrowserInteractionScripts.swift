import Foundation

enum KajiBrowserInteractionScripts {
    static func click(_ request: KajiBrowserClickRequest) -> String {
        let target = KajiBrowserJavaScript.literal(request.target ?? "")
        let selector = KajiBrowserJavaScript.literal(request.selector ?? "")
        let button = KajiBrowserJavaScript.literal(request.button)
        let x = request.x.map { String($0) } ?? "null"
        let y = request.y.map { String($0) } ?? "null"
        return wrap("""
        const point = \(x) !== null && \(y) !== null ? { x: \(x), y: \(y) } : null;
        const el = point ? document.elementFromPoint(point.x, point.y) : find(\(target), \(selector));
        if (!el) return fail('not_found');
        const resolved = point || center(el);
        const kind = \(button);
        if (kind === 'right') {
          fire(el, 'contextmenu', resolved, 2);
          return ok();
        }
        fire(el, 'pointerdown', resolved, kind === 'middle' ? 1 : 0);
        fire(el, 'mousedown', resolved, kind === 'middle' ? 1 : 0);
        fire(el, 'pointerup', resolved, kind === 'middle' ? 1 : 0);
        fire(el, 'mouseup', resolved, kind === 'middle' ? 1 : 0);
        fire(el, 'click', resolved, kind === 'middle' ? 1 : 0);
        if (\(request.doubleClick ? "true" : "false")) fire(el, 'dblclick', resolved, 0);
        return ok();
        """)
    }

    static func hover(target: String?, selector: String?) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        return wrap("""
        const el = find(\(target), \(selector));
        if (!el) return fail('not_found');
        const point = center(el);
        fire(el, 'pointerover', point, 0);
        fire(el, 'mouseover', point, 0);
        fire(el, 'pointermove', point, 0);
        fire(el, 'mousemove', point, 0);
        return ok();
        """)
    }

    static func drag(startTarget: String?, endTarget: String?) -> String {
        let start = KajiBrowserJavaScript.literal(startTarget ?? "")
        let end = KajiBrowserJavaScript.literal(endTarget ?? "")
        return wrap("""
        const source = find(\(start), '');
        const dest = find(\(end), '');
        if (!source || !dest) return fail('not_found');
        const a = center(source);
        const b = center(dest);
        const data = new DataTransfer();
        const init = point => ({ bubbles: true, cancelable: true, dataTransfer: data, clientX: point.x, clientY: point.y });
        source.dispatchEvent(new DragEvent('dragstart', init(a)));
        dest.dispatchEvent(new DragEvent('dragenter', init(b)));
        dest.dispatchEvent(new DragEvent('dragover', init(b)));
        dest.dispatchEvent(new DragEvent('drop', init(b)));
        source.dispatchEvent(new DragEvent('dragend', init(b)));
        return ok();
        """)
    }

    static func pressKey(_ key: String) -> String {
        let key = KajiBrowserJavaScript.literal(key)
        return wrap("""
        const active = document.activeElement || document.body;
        const combo = parseKey(\(key));
        for (const type of ['keydown', 'keypress', 'keyup']) {
          active.dispatchEvent(new KeyboardEvent(type, {
            key: combo.key,
            code: combo.code,
            bubbles: true,
            cancelable: true,
            metaKey: combo.meta,
            ctrlKey: combo.ctrl,
            altKey: combo.alt,
            shiftKey: combo.shift
          }));
        }
        if (combo.key === 'Enter' && active && active.form) active.form.requestSubmit && active.form.requestSubmit();
        return ok();
        """)
    }

    private static func wrap(_ body: String) -> String {
        KajiBrowserScriptRuntime.wrap(body)
    }
}
