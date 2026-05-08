import Foundation
import Testing

@testable import Droid

@MainActor
struct AgentSessionBookmarkTests {
    @Test
    func storeDedupesByProviderAndSessionID() {
        let store = AgentSessionBookmarkStore(inMemory: true)
        let candidate = AgentSessionBookmarkCandidate(
            paneID: UUID(),
            provider: .opencode,
            sessionID: "session-1",
            title: "OpenCode",
            projectID: UUID(),
            worktreeID: UUID(),
            worktreePath: "/tmp/muxy",
            areaID: UUID(),
            tabID: UUID()
        )

        store.save([candidate], folderName: "Agents")
        store.save([candidate], folderName: "Agents")

        #expect(store.bookmarks.count == 1)
        #expect(store.bookmarks.first?.sessionID == "session-1")
        #expect(store.bookmarks.first?.folderName == "Agents")
    }

    @Test
    func paletteShowsBookmarkCandidatesForSlashCommand() {
        let candidate = AgentSessionBookmarkCandidate(
            paneID: UUID(),
            provider: .codex,
            sessionID: "codex-session",
            title: "Codex task",
            projectID: UUID(),
            worktreeID: UUID(),
            worktreePath: "/tmp/muxy",
            areaID: UUID(),
            tabID: UUID()
        )

        let entries = AskPaletteEntries.build(.init(
            fieldText: "/bookmark",
            prompt: "",
            projects: [],
            worktrees: [],
            provider: .terminal,
            sessionMode: .bestMatch,
            sessions: [],
            bookmarkCandidates: [candidate],
            historyOptions: [],
            skillOptions: [],
            projectName: "muxy",
            worktreeName: "main"
        ))

        #expect(entries.count == 1)
        #expect(entries.first?.title == "Codex task")
    }
}
