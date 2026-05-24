import Foundation
import os

private let ghosttyDiagnosticsLogger = Logger(subsystem: "app.kaji", category: "GhosttyRuntimeDiagnostics")

enum GhosttyRuntimeDiagnostics {
    static func log(configPath: String) {
        let resources = getenv("GHOSTTY_RESOURCES_DIR").map { String(cString: $0) } ?? "unset"
        ghosttyDiagnosticsLogger.info("Ghostty runtime resources=\(resources, privacy: .public) config=\(configPath, privacy: .public)")
    }
}
