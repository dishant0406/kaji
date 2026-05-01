import Foundation

@MainActor
enum TerminalCommandInjector {
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
