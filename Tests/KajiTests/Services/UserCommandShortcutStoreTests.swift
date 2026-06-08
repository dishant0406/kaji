import Foundation
import Testing

@testable import Kaji

@MainActor
struct UserCommandShortcutStoreTests {
    @Test
    func normalizesSlugFromName() {
        #expect(UserCommandShortcutValidator.slug(from: "Run Tests!") == "runtests")
        #expect(UserCommandShortcutValidator.slug(from: "Deploy_prod 2") == "deployprod2")
    }

    @Test
    func savesLoadsAndResolvesShortcut() throws {
        let file = try shortcutsFile()
        let store = UserCommandShortcutStore(fileStore: CodableFileStore(fileURL: file, options: .prettySorted))
        var draft = UserCommandShortcutDraft()
        draft.name = "Run Tests"
        draft.slug = "runtests"
        draft.command = "swift test"

        let result = store.save(draft)
        let reloaded = UserCommandShortcutStore(fileStore: CodableFileStore(fileURL: file, options: .prettySorted))

        #expect(result.canSave)
        #expect(reloaded.resolve(slug: "runtests")?.command == "swift test")
    }

    @Test
    func rejectsInvalidDrafts() throws {
        let store = UserCommandShortcutStore(fileStore: CodableFileStore(fileURL: try shortcutsFile(), options: .prettySorted))
        store.save(draft(name: "Run Tests", slug: "runtests", command: "swift test"))

        #expect(store.validation(for: draft(name: "", slug: "build", command: "swift build")).errors.contains(.nameRequired))
        #expect(store.validation(for: draft(name: "Build", slug: "build-all", command: "swift build")).errors.contains(.slugInvalid))
        #expect(store.validation(for: draft(name: "Git", slug: "git", command: "git status")).errors.contains(.slugReserved))
        #expect(store.validation(for: draft(name: "Duplicate", slug: "runtests", command: "swift test")).errors.contains(.slugConflict))
        #expect(store.validation(for: draft(name: "Empty", slug: "empty", command: "")).errors.contains(.commandRequired))
        #expect(store.validation(for: draft(name: "Bad", slug: "bad", command: "echo {bad-name}")).errors.contains {
            if case .templateInvalid = $0 { return true }
            return false
        })
    }

    private func draft(name: String, slug: String, command: String) -> UserCommandShortcutDraft {
        var draft = UserCommandShortcutDraft()
        draft.name = name
        draft.slug = slug
        draft.command = command
        return draft
    }

    private func shortcutsFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("user-command-shortcuts.json")
    }
}
