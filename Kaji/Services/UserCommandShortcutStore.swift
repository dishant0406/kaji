import Foundation
import os

private let userCommandShortcutLogger = Logger(subsystem: "app.kaji", category: "UserCommandShortcutStore")

@MainActor
@Observable
final class UserCommandShortcutStore {
    static let shared = UserCommandShortcutStore()

    private(set) var shortcuts: [UserCommandShortcut] = []
    private let fileStore: CodableFileStore<[UserCommandShortcut]>

    init(
        fileStore: CodableFileStore<[UserCommandShortcut]> = CodableFileStore(
            fileURL: KajiFileStorage.fileURL(filename: "user-command-shortcuts.json"),
            options: .prettySorted
        )
    ) {
        self.fileStore = fileStore
        load()
    }

    var sortedShortcuts: [UserCommandShortcut] {
        shortcuts.sorted { first, second in
            first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    func resolve(slug: String) -> UserCommandShortcut? {
        let normalized = UserCommandShortcutValidator.slug(from: slug)
        return shortcuts.first { $0.slug == normalized }
    }

    func validation(for draft: UserCommandShortcutDraft) -> UserCommandShortcutValidation {
        UserCommandShortcutValidator.validate(draft: draft, existing: shortcuts)
    }

    @discardableResult
    func save(_ draft: UserCommandShortcutDraft) -> UserCommandShortcutValidation {
        var normalizedDraft = draft
        normalizedDraft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedDraft.slug = UserCommandShortcutValidator.slug(from: draft.slug)
        normalizedDraft.command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = validation(for: normalizedDraft)
        guard result.canSave else { return result }

        let now = Date()
        if let id = normalizedDraft.id, let index = shortcuts.firstIndex(where: { $0.id == id }) {
            shortcuts[index].name = normalizedDraft.name
            shortcuts[index].slug = normalizedDraft.slug
            shortcuts[index].command = normalizedDraft.command
            shortcuts[index].updatedAt = now
        } else {
            shortcuts.append(UserCommandShortcut(
                name: normalizedDraft.name,
                slug: normalizedDraft.slug,
                command: normalizedDraft.command,
                createdAt: now,
                updatedAt: now
            ))
        }
        persist()
        return result
    }

    func delete(_ shortcut: UserCommandShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        persist()
    }

    private func load() {
        do {
            shortcuts = try fileStore.load() ?? []
        } catch {
            userCommandShortcutLogger.error("Failed to load user command shortcuts: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            try fileStore.save(shortcuts)
        } catch {
            userCommandShortcutLogger.error("Failed to save user command shortcuts: \(error.localizedDescription)")
        }
    }
}
