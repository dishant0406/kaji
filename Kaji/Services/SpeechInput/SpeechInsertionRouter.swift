import AppKit
import Foundation
import WebKit

@MainActor
final class SpeechInsertionRouter: SpeechInserting {
    private let editorProvider: () -> EditorTabState?

    init(editorProvider: @escaping () -> EditorTabState?) {
        self.editorProvider = editorProvider
    }

    func insert(_ text: String) throws {
        guard !text.isEmpty else { throw SpeechInputError.emptyTranscript }
        let responder = NSApp.keyWindow?.firstResponder
        if let terminal = responder?.nearestResponder(of: TermyTerminalNSView.self) {
            terminal.sendText(text)
            return
        }
        if let textView = responder?.nearestResponder(of: NSTextView.self) {
            textView.insertText(text, replacementRange: textView.selectedRange())
            return
        }
        if let webView = responder?.nearestResponder(of: WKWebView.self) {
            if isMonacoEditor(webView), let editor = editorProvider() {
                editor.insertSpeechText(text)
                return
            }
            insertIntoWebView(webView, text: text)
            return
        }
        if let editor = editorProvider() {
            editor.insertSpeechText(text)
            return
        }
        throw SpeechInputError.noInsertionTarget
    }

    private func isMonacoEditor(_ webView: WKWebView) -> Bool {
        webView.url?.query?.contains("editorID=") == true
    }

    private func insertIntoWebView(_ webView: WKWebView, text: String) {
        let encoded = jsonLiteral(for: text)
        let script = """
        (() => {
          const text = \(encoded);
          const active = document.activeElement;
          if (!active) return false;
          const tag = active.tagName;
          if (active.isContentEditable) {
            document.execCommand('insertText', false, text);
            return true;
          }
          if (tag === 'TEXTAREA' || tag === 'INPUT') {
            const start = active.selectionStart ?? active.value.length;
            const end = active.selectionEnd ?? active.value.length;
            active.value = active.value.slice(0, start) + text + active.value.slice(end);
            active.selectionStart = start + text.length;
            active.selectionEnd = start + text.length;
            active.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
            active.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          }
          return false;
        })()
        """
        webView.evaluateJavaScript(script)
    }

    private func jsonLiteral(for text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let literal = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return literal
    }
}

private extension NSResponder {
    func nearestResponder<T>(of type: T.Type) -> T? {
        var current: NSResponder? = self
        while let responder = current {
            if let match = responder as? T {
                return match
            }
            current = responder.nextResponder
        }
        return nil
    }
}
