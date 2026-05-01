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
                historyOptions: [],
                skillOptions: [],
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
                historyOptions: [],
                skillOptions: [],
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
                historyOptions: [],
                skillOptions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.count == 1)
        #expect(entries.first?.title == "Codex")
    }

    @Test
    @MainActor
    func providerAnnotationWithoutPromptShowsLaunchEntry() {
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: ":t:opencode",
                prompt: "",
                projects: [],
                worktrees: [],
                provider: .opencode,
                sessionMode: .bestMatch,
                sessions: [],
                historyOptions: [],
                skillOptions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.first?.title == "Open OpenCode")
    }

    @Test
    @MainActor
    func historyAnnotationShowsHistoryOptions() {
        let history = AskHistoryOption(
            provider: .codex,
            sessionID: "session-1",
            title: "Fix tests",
            detail: "Codex in muxy",
            projectPath: "/tmp/muxy",
            updatedAt: Date()
        )
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: ":t:codex :h:",
                prompt: "",
                projects: [],
                worktrees: [],
                provider: .codex,
                sessionMode: .bestMatch,
                sessions: [],
                historyOptions: [history],
                skillOptions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.first?.title == "Fix tests")
    }

    @Test
    @MainActor
    func skillAnnotationShowsSkillOptions() {
        let skill = AskSkillOption(
            name: "copywriting",
            title: "Write marketing copy",
            detail: "Agents skill",
            path: "/tmp/copywriting/SKILL.md",
            source: "Agents"
        )
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: ":t:claude :s:copy",
                prompt: "",
                projects: [],
                worktrees: [],
                provider: .claude,
                sessionMode: .bestMatch,
                sessions: [],
                historyOptions: [],
                skillOptions: [skill],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.first?.title == "copywriting")
    }

    @Test
    @MainActor
    func terminalHistoryAnnotationShowsNoOptions() {
        let history = AskHistoryOption(
            provider: .terminal,
            sessionID: "session-1",
            title: "Shell work",
            detail: "Terminal in muxy",
            projectPath: "/tmp/muxy",
            updatedAt: Date()
        )
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: ":t:terminal :h:",
                prompt: "",
                projects: [],
                worktrees: [],
                provider: .terminal,
                sessionMode: .bestMatch,
                sessions: [],
                historyOptions: [history],
                skillOptions: [],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.isEmpty)
    }

    @Test
    @MainActor
    func terminalSkillAnnotationShowsNoOptions() {
        let skill = AskSkillOption(
            name: "copywriting",
            title: "Write marketing copy",
            detail: "Agents skill",
            path: "/tmp/copywriting/SKILL.md",
            source: "Agents"
        )
        let entries = AskPaletteEntries.build(
            .init(
                fieldText: ":t:terminal :s:",
                prompt: "",
                projects: [],
                worktrees: [],
                provider: .terminal,
                sessionMode: .bestMatch,
                sessions: [],
                historyOptions: [],
                skillOptions: [skill],
                projectName: "muxy",
                worktreeName: "main"
            )
        )

        #expect(entries.isEmpty)
    }
}
