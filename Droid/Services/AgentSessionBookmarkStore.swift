import Foundation

@MainActor
@Observable
final class AgentSessionBookmarkStore {
    static let shared = AgentSessionBookmarkStore()

    private(set) var bookmarks: [AgentSessionBookmark] = []
    private let fileStore: CodableFileStore<[AgentSessionBookmark]>?

    var folderNames: [String] {
        Array(Set(bookmarks.map(\.folderName)))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    init(fileStore: CodableFileStore<[AgentSessionBookmark]>? = nil) {
        let fileStore = fileStore ?? AgentSessionBookmarkStore.defaultFileStore()
        self.fileStore = fileStore
        bookmarks = (try? fileStore?.load()) ?? []
    }

    init(inMemory: Bool) {
        _ = inMemory
        fileStore = nil
        bookmarks = []
    }

    func save(_ candidates: [AgentSessionBookmarkCandidate], folderName: String) {
        let folderName = normalizedFolderName(folderName)
        let now = Date()
        for candidate in candidates {
            let sessionID = candidate.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionID.isEmpty else { continue }
            if let index = bookmarks.firstIndex(where: {
                $0.providerID == candidate.provider.rawValue && $0.sessionID == sessionID
            }) {
                bookmarks[index].updatedAt = now
                continue
            }
            bookmarks.insert(AgentSessionBookmark(
                id: UUID(),
                providerID: candidate.provider.rawValue,
                providerTitle: candidate.provider.title,
                sessionID: sessionID,
                title: candidate.title,
                folderName: folderName,
                projectID: candidate.projectID,
                worktreeID: candidate.worktreeID,
                worktreePath: candidate.worktreePath,
                createdAt: now,
                updatedAt: now
            ), at: 0)
        }
        persist()
    }

    func normalizedFolderName(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "General" : cleaned
    }

    func reset() {
        bookmarks = []
        persist()
    }

    private func persist() {
        try? fileStore?.save(bookmarks)
    }

    private static func defaultFileStore() -> CodableFileStore<[AgentSessionBookmark]>? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.processName.hasSuffix("PackageTests")
        {
            return nil
        }
        return CodableFileStore(fileURL: DroidFileStorage.fileURL(filename: "agent-session-bookmarks.json"), options: .prettySorted)
    }
}
