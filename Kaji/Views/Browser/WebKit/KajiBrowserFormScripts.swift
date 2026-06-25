import Foundation

enum KajiBrowserFormScripts {
    static func fill(target: String?, selector: String?, text: String, append: Bool) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        let text = KajiBrowserJavaScript.literal(text)
        return KajiBrowserScriptRuntime.wrap("""
        const el = find(\(target), \(selector));
        if (!el) return fail('not_found');
        center(el);
        setText(el, \(text), \(append ? "true" : "false"));
        return ok();
        """)
    }

    static func fillForm(fields: [[String: Any]]) -> String {
        let data = json(fields)
        return KajiBrowserScriptRuntime.wrap("""
        const fields = \(data);
        const results = [];
        for (const field of fields) {
          const el = find(field.target || field.ref || '', field.selector || '');
          if (!el) {
            results.push({ ok: false, error: 'not_found', field });
            continue;
          }
          center(el);
          setText(el, String(field.value ?? field.text ?? ''), false);
          results.push({ ok: true, target: field.target || field.selector || '' });
        }
        const failed = results.find(item => !item.ok);
        return failed ? fail('field_not_found') : ok({ results });
        """)
    }

    static func selectOption(target: String?, selector: String?, values: [String]) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        let values = json(values)
        return KajiBrowserScriptRuntime.wrap("""
        const el = find(\(target), \(selector));
        if (!el) return fail('not_found');
        if (!(el instanceof HTMLSelectElement)) return fail('not_select');
        const values = new Set(\(values).map(String));
        for (const option of el.options) {
          option.selected = values.has(option.value) || values.has(option.label) || values.has(option.text);
        }
        emitInput(el);
        return ok({ values: Array.from(el.selectedOptions).map(option => option.value) });
        """)
    }

    static func upload(target: String?, selector: String?, files: [[String: String]]) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        let files = json(files)
        return KajiBrowserScriptRuntime.wrap("""
        const el = find(\(target), \(selector)) || document.querySelector('input[type="file"]');
        if (!el) return fail('not_found');
        if (!(el instanceof HTMLInputElement) || el.type !== 'file') return fail('not_file_input');
        const transfer = new DataTransfer();
        for (const item of \(files)) {
          const binary = atob(item.base64 || '');
          const bytes = new Uint8Array(binary.length);
          for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
          transfer.items.add(new File([bytes], item.name, { type: item.mime || 'application/octet-stream' }));
        }
        el.files = transfer.files;
        emitInput(el);
        return ok({ count: el.files.length });
        """)
    }

    static func drop(target: String?, selector: String?, data: [[String: String]], files: [[String: String]]) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        let data = json(data)
        let files = json(files)
        return KajiBrowserScriptRuntime.wrap("""
        const el = find(\(target), \(selector));
        if (!el) return fail('not_found');
        const point = center(el);
        const transfer = new DataTransfer();
        for (const item of \(data)) transfer.setData(item.mime || 'text/plain', item.value || '');
        for (const item of \(files)) {
          const binary = atob(item.base64 || '');
          const bytes = new Uint8Array(binary.length);
          for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
          transfer.items.add(new File([bytes], item.name, { type: item.mime || 'application/octet-stream' }));
        }
        for (const type of ['dragenter', 'dragover', 'drop']) {
          const init = { bubbles: true, cancelable: true, dataTransfer: transfer, clientX: point.x, clientY: point.y };
          el.dispatchEvent(new DragEvent(type, init));
        }
        return ok();
        """)
    }

    private static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }
}
