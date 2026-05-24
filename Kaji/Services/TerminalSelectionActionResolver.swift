import AppKit
import Foundation

struct TerminalSelectionAction: Equatable {
    let title: String
    let url: URL
}

enum TerminalSelectionActionResolver {
    static func action(from selection: String?, workingDirectory: String) -> TerminalSelectionAction? {
        guard let token = token(from: selection) else { return nil }
        if let url = URL(string: token), let scheme = url.scheme, ["http", "https"].contains(scheme) {
            return TerminalSelectionAction(title: "Open Link", url: url)
        }
        let path = resolvedPath(token, workingDirectory: workingDirectory)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return TerminalSelectionAction(title: "Open File", url: URL(fileURLWithPath: path))
    }

    static func open(_ action: TerminalSelectionAction) {
        NSWorkspace.shared.open(action.url)
    }

    private static func token(from selection: String?) -> String? {
        guard let selection else { return nil }
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let first = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
        let stripped = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return stripped.isEmpty ? nil : stripped
    }

    private static func resolvedPath(_ token: String, workingDirectory: String) -> String {
        let expanded = token.replacingOccurrences(of: "~", with: NSHomeDirectory(), options: .anchored)
        if expanded.hasPrefix("/") { return expanded }
        return URL(fileURLWithPath: workingDirectory).appendingPathComponent(expanded).standardized.path
    }
}
