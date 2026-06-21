import Foundation

enum MonacoDiagnosticMapper {
    static func diagnostics(
        for markers: [MonacoDiagnosticMarker],
        filePath: String,
        projectPath: String
    ) -> [EditorDiagnostic] {
        let relativePath = relativePath(for: filePath, projectPath: projectPath)
        return markers.map { marker in
            let line = max(1, marker.startLineNumber)
            let column = max(1, marker.startColumn)
            return EditorDiagnostic(
                id: "\(filePath):\(line):\(column):\(marker.endLineNumber):\(marker.endColumn):\(marker.message)",
                filePath: filePath,
                relativePath: relativePath,
                line: line,
                column: column,
                severity: severity(marker.severity),
                message: marker.message,
                source: marker.source ?? "Monaco"
            )
        }
    }

    private static func severity(_ value: Int) -> EditorDiagnosticSeverity {
        switch value {
        case 8: .error
        case 4: .warning
        case 1: .hint
        default: .information
        }
    }

    private static func relativePath(for filePath: String, projectPath: String) -> String {
        let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        guard filePath.hasPrefix(prefix) else { return URL(fileURLWithPath: filePath).lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }
}
