import Foundation
import Testing

@testable import Droid

struct AskPaletteEntriesTests {
    @Test
    func slashStateParsesCommandAndFilter() {
        let state = AskPaletteEntries.slashState(for: "/provider cod")

        #expect(state?.token == "provider")
        #expect(state?.command == .provider)
        #expect(state?.filter == "cod")
    }

    @Test
    @MainActor
    func slashEntriesReturnFilteredProviderOptions() {
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: "/provider codex",
                prompt: "hello",
                projects: [],
                worktrees: [],
                provider: .terminal,
                sessionMode: .bestMatch,
                sessions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.count == 1)
        #expect(entries.first?.title == "Codex")
    }

    @Test
    @MainActor
    func emptyPromptShowsSlashCommands() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: "",
                prompt: "",
                projects: [project],
                worktrees: [],
                provider: .codex,
                sessionMode: .bestMatch,
                sessions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.map(\.title).contains("Project"))
        #expect(entries.map(\.title).contains("Provider"))
        #expect(entries.first(where: { $0.title == "Project" })?.annotation == "/project")
    }

    @Test
    @MainActor
    func inlineAnnotationShowsRelevantAutocomplete() {
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: "what is this :t:co",
                prompt: "what is this",
                projects: [],
                worktrees: [],
                provider: .terminal,
                sessionMode: .bestMatch,
                sessions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.count == 1)
        #expect(entries.first?.title == "Codex")
    }
}
