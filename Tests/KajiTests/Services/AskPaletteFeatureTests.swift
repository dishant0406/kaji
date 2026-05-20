import Foundation
import Testing

@testable import Kaji

struct AskPaletteFeatureTests {
    @Test
    func taskAnnotationShowsRecipes() {
        let recipe = AskTaskRecipe.user(name: "Ship Fix", prompt: "Fix and test", projectID: nil)
        let entries = AskPaletteEntries.build(context(fieldText: ":task:ship", taskRecipes: [recipe]))

        #expect(entries.first?.action == .taskRecipe(recipe))
    }

    @Test
    func taskAddAnnotationShowsFormEntry() {
        let entries = AskPaletteEntries.build(context(fieldText: ":ta:"))

        #expect(entries.first?.action == .openTaskForm)
    }

    @Test
    func taskEditAnnotationShowsEditableSavedTasks() {
        let recipe = AskTaskRecipe.user(name: "Smoke", prompt: "Run smoke", projectID: nil)
        let entries = AskPaletteEntries.build(context(fieldText: ":te:sm", taskRecipes: [recipe]))

        #expect(entries.first?.action == .editTaskRecipe(recipe))
    }

    @Test
    func mentionShowsFileAndFolderOptions() {
        let option = AskMentionOption(path: "Kaji/App.swift", kind: .file)
        let entries = AskPaletteEntries.build(context(fieldText: "review @App", mentionOptions: [option]))

        #expect(entries.first?.action == .mention(option))
    }

    @Test
    func addProjectShowsDirectoryOptions() {
        let option = AskDirectoryOption(path: "/Users/dishants/projects/muxy")
        let entries = AskPaletteEntries.build(context(fieldText: ":pa:~/projects/m", directoryOptions: [option]))

        #expect(entries.first?.action == .directory(option))
    }

    @Test
    func attachAnnotationShowsAttachAction() {
        let entries = AskPaletteEntries.build(context(fieldText: ":attach:"))

        #expect(entries.first?.action == .attach)
    }

    @Test
    func diffAnnotationShowsSummaryAndChangedFiles() {
        let projectID = UUID()
        let worktreeID = UUID()
        let changed = GitStatusFile(
            path: "Kaji/App.swift",
            oldPath: nil,
            xStatus: "M",
            yStatus: " ",
            additions: 2,
            deletions: 1,
            isBinary: false
        )
        let diffFile = DiffPaletteFile(
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: "/repo",
            file: changed,
            isStaged: true
        )

        let entries = AskPaletteEntries.build(context(fieldText: ":diff:", diffFiles: [diffFile]))

        #expect(entries.count == 2)
        #expect(entries[0].action == .openDiffSummary(projectID: projectID, worktreeID: worktreeID, worktreePath: "/repo"))
        #expect(entries[1].action == .diffFile(diffFile))
        #expect(entries[1].detail == "Staged • +2 -1")
        #expect(entries[1].annotation == "M +2 -1")
    }

    private func context(
        fieldText: String,
        taskRecipes: [AskTaskRecipe] = [],
        mentionOptions: [AskMentionOption] = [],
        directoryOptions: [AskDirectoryOption] = [],
        diffFiles: [DiffPaletteFile] = []
    ) -> AskPaletteContext {
        AskPaletteContext(
            fieldText: fieldText,
            prompt: fieldText,
            projects: [],
            worktrees: [],
            provider: .opencode,
            sessionMode: .bestMatch,
            sessions: [],
            historyOptions: [],
            skillOptions: [],
            taskRecipes: taskRecipes,
            mentionOptions: mentionOptions,
            directoryOptions: directoryOptions,
            diffFiles: diffFiles,
            projectName: "muxy",
            worktreeName: "main"
        )
    }
}
