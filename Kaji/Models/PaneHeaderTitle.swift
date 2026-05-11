import Foundation

@MainActor
enum PaneHeaderTitle {
    @MainActor
    static func resolve(for area: TabArea) -> String {
        guard let tab = area.activeTab else {
            return projectName(from: area.projectPath)
        }

        switch tab.content {
        case let .terminal(pane):
            return terminalTitle(for: pane, fallbackPath: area.projectPath)
        case .vcs:
            return "Source Control"
        case let .editor(state):
            return state.displayTitle
        case let .diffViewer(state):
            return state.displayTitle
        case .parentAgent:
            return "Kaji"
        case .codeGraph:
            return "Code Graph"
        case let .browser(state):
            return state.title
        }
    }

    private static func terminalTitle(for pane: TerminalPaneState, fallbackPath: String) -> String {
        let trimmed = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return projectName(from: fallbackPath)
        }
        if trimmed == "Terminal" {
            return projectName(from: fallbackPath)
        }
        if let promptPath = promptPathTitle(from: trimmed) {
            return promptPath
        }
        return trimmed
    }

    private static func promptPathTitle(from title: String) -> String? {
        guard let colonIndex = title.lastIndex(of: ":") else { return nil }
        let rawPath = title[title.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawPath.contains("/") || rawPath == "~" else { return nil }

        let segments = rawPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)

        guard let last = segments.last else {
            return rawPath == "~" ? "Home" : nil
        }
        return last == "~" ? "Home" : last
    }

    private static func projectName(from path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Terminal" : name
    }
}
