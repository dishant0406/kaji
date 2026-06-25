import Foundation

enum KajiBrowserWaitScripts {
    static func selector(target: String?, selector: String?) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        return KajiBrowserScriptRuntime.wrap("""
        const el = find(\(target), \(selector));
        if (!el) return { ok: true, found: false };
        const style = getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return { ok: true, found: rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' };
        """)
    }

    static func text(_ text: String, gone: Bool) -> String {
        let text = KajiBrowserJavaScript.literal(text)
        return """
        (() => {
          const found = ((document.body && document.body.innerText) || '').includes(\(text));
          return \(gone ? "!found" : "found");
        })()
        """
    }
}
