import Foundation

enum MarkdownPreviewResourceLoader {
    static func shellHTML() -> String {
        let template = text("preview", "html") ?? fallbackHTML
        let style = [text("katex.min", "css", subdirectory: vendor), text("preview", "css")]
            .compactMap(\.self)
            .joined(separator: "\n")
            .replacingOccurrences(of: "url(fonts/", with: "url(kaji-preview-asset:///fonts/")
            .replacingOccurrences(of: "kaji-preview-asset:///fonts/", with: "kaji-preview-asset:///")
        let scripts = scriptNames.compactMap { name -> String? in
            guard let script = text(name, "js", subdirectory: vendor) ?? text(name, "js") else { return nil }
            return "<script>\n\(script)\n</script>"
        }.joined(separator: "\n")
        return template
            .replacingOccurrences(of: "{{STYLE}}", with: style)
            .replacingOccurrences(of: "{{SCRIPTS}}", with: scripts)
    }

    static var resourceRoot: URL? {
        Bundle.appResources.url(forResource: "MarkdownPreview", withExtension: nil) ?? Bundle.appResources.resourceURL
    }

    private static let vendor = "MarkdownPreview/vendor"
    private static let scriptNames = ["markdown-it.min", "purify.min", "katex.min", "auto-render.min", "mermaid.min", "preview"]

    private static var fallbackHTML: String {
        """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><style>html,body{margin:0;background:#0b0b0c;color:#f4f4f5}</style></head>
        <body><main id="content"></main>{{SCRIPTS}}</body>
        </html>
        """
    }

    private static func text(_ name: String, _ ext: String, subdirectory: String? = "MarkdownPreview") -> String? {
        guard let url = Bundle.appResources.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.appResources.url(forResource: name, withExtension: ext)
        else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
