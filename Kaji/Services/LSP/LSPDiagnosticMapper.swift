import Foundation

enum LSPDiagnosticMapper {
    static func editorDiagnostics(
        params: LSPPublishDiagnosticsParams,
        projectPath: String,
        fallbackSource: String?
    ) -> [EditorDiagnostic] {
        guard let fileURL = URL(string: params.uri), fileURL.isFileURL else { return [] }
        let filePath = fileURL.path
        let relativePath = relativePath(for: filePath, projectPath: projectPath)
        return params.diagnostics.map { diagnostic in
            let line = diagnostic.range.start.line + 1
            let column = diagnostic.range.start.character + 1
            return EditorDiagnostic(
                id: "\(filePath):\(line):\(column):\(diagnostic.message)",
                filePath: filePath,
                relativePath: relativePath,
                line: line,
                column: column,
                severity: severity(diagnostic.severity),
                message: diagnostic.message,
                source: diagnostic.source ?? fallbackSource
            )
        }
    }

    private static func severity(_ value: Int?) -> EditorDiagnosticSeverity {
        switch value {
        case 1: .error
        case 2: .warning
        case 3: .information
        case 4: .hint
        default: .information
        }
    }

    private static func relativePath(for filePath: String, projectPath: String) -> String {
        let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        guard filePath.hasPrefix(prefix) else { return URL(fileURLWithPath: filePath).lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }
}
