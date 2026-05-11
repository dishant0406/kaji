import Foundation

@MainActor
enum TerminalCommandInjector {
    static func interrupt(_ paneID: UUID, escapeCount: Int = 1) -> Bool {
        guard let view = TerminalViewRegistry.shared.view(for: paneID), view.hasLiveSurface else { return false }
        for _ in 0 ..< max(escapeCount, 1) {
            view.sendEscapeKey()
        }
        return true
    }

    static func submit(_ text: String, into paneID: UUID) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for _ in 0 ..< 80 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let view = TerminalViewRegistry.shared.view(for: paneID), view.hasLiveSurface else { continue }
            view.sendText(trimmed)
            view.sendReturnKey()
            return true
        }
        return false
    }
}
