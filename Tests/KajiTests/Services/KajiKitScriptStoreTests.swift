import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiKitScriptStoreTests {
    @Test
    func normalizesSlug() {
        #expect(KajiKitScriptStore.normalizedSlug("Commit & Push") == "commit-push")
        #expect(KajiKitScriptStore.normalizedSlug("  Fix___Checks  ") == "fix-checks")
    }

    @Test
    func savesAndResolvesProjectScriptBeforeGlobal() throws {
        let file = try scriptsFile()
        let store = KajiKitScriptStore(scriptsFile: file)
        let projectID = UUID()

        store.save(.init(title: "Global Build", slug: "build", scope: .global, command: "swift build"), projectID: projectID)
        store.save(.init(title: "Project Build", slug: "build", scope: .project, command: "scripts/build.sh"), projectID: projectID)

        #expect(store.resolve(slug: "build", projectID: projectID)?.title == "Project Build")
        #expect(store.resolve(slug: "build", projectID: UUID())?.title == "Global Build")
    }

    @Test
    func detectsRiskyCommands() {
        let safe = script(command: "swift test")
        let risky = script(command: "git reset --hard HEAD")

        #expect(!KajiKitScriptPlanner.isRisky(safe))
        #expect(KajiKitScriptPlanner.isRisky(risky))
    }

    private func script(command: String) -> KajiKitScript {
        KajiKitScript(title: "Script", slug: "script", scope: .global, projectID: nil, kind: .command, command: command)
    }

    private func scriptsFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("scripts.json")
    }
}

private extension KajiKitScriptDraft {
    init(title: String, slug: String, scope: KajiKitScriptScope, command: String) {
        self.init()
        self.title = title
        self.slug = slug
        self.scope = scope
        self.command = command
    }
}
