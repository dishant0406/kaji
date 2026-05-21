import Foundation

@MainActor
@Observable
final class ChildAgentFeedStore {
    static let shared = ChildAgentFeedStore()

    private(set) var feeds: [UUID: ChildAgentFeed] = [:]
    private let maxEntries = 24
    private let maxFeeds = 80

    private init() {}

    func feed(for runID: UUID) -> ChildAgentFeed? {
        feeds[runID]
    }

    func append(runID: UUID, kind: ChildAgentFeedEntryKind, text: String) {
        let trimmed = normalized(text, lineLimit: kind == .terminal ? 40 : 12)
        guard !trimmed.isEmpty else { return }
        var feed = feeds[runID] ?? ChildAgentFeed(id: runID)
        if feed.entries.last?.text == trimmed { return }
        feed.entries = Array((feed.entries + [ChildAgentFeedEntry(kind: kind, text: trimmed)]).suffix(maxEntries))
        if kind == .final {
            feed.finalAnswer = trimmed
        }
        if kind == .terminal {
            feed.terminalOutput = trimmed
        }
        feed.updatedAt = Date()
        feeds[runID] = feed
        pruneFeeds()
    }

    func recentText(runID: UUID, limit: Int = 6) -> [String] {
        Array((feeds[runID]?.entries ?? []).suffix(limit)).map(\.text)
    }

    func finalAnswer(runID: UUID) -> String? {
        feeds[runID]?.finalAnswer
    }

    func terminalOutput(runID: UUID) -> String? {
        feeds[runID]?.terminalOutput
    }

    private func normalized(_ text: String, lineLimit: Int) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(lineLimit)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pruneFeeds() {
        guard feeds.count > maxFeeds else { return }
        let keep = Set(feeds.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxFeeds).map(\.id))
        feeds = feeds.filter { keep.contains($0.key) }
    }
}
