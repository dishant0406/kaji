import SwiftUI

struct UserCommandShortcutSettingsSection: View {
    let searchText: String
    @State private var store = UserCommandShortcutStore.shared
    @State private var draft = UserCommandShortcutDraft()
    @State private var isEditing = false
    @State private var slugWasEdited = false
    @State private var pendingDelete: UserCommandShortcut?

    var body: some View {
        SettingsSection("Command Shortcuts", showsDivider: false) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isEditing {
                    UserCommandShortcutForm(
                        draft: $draft,
                        validation: validation,
                        onNameChange: updateName,
                        onSlugChange: updateSlug,
                        onSave: save,
                        onCancel: cancel
                    )
                }
                if filteredShortcuts.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredShortcuts) { shortcut in
                        UserCommandShortcutRow(
                            shortcut: shortcut,
                            onEdit: { edit(shortcut) },
                            onDelete: { pendingDelete = shortcut }
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Command Shortcut?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePendingShortcut)
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the ::\(pendingDelete?.slug ?? "") command shortcut.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run saved terminal commands with ::slug in Command-K.")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text("Commands run in the active worktree and show output in Command-K.")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
            Button(isEditing ? "Editing" : "New Command") {
                startNew()
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            .disabled(isEditing && draft.id == nil)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
    }

    private var emptyState: some View {
        Text(normalizedSearch.isEmpty ? "No command shortcuts yet." : "No matching command shortcuts.")
            .kajiFont(size: 12)
            .foregroundStyle(KajiTheme.fgDim)
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }

    private var validation: UserCommandShortcutValidation {
        store.validation(for: draft)
    }

    private var filteredShortcuts: [UserCommandShortcut] {
        let query = normalizedSearch
        guard !query.isEmpty else { return store.sortedShortcuts }
        return store.sortedShortcuts.filter { shortcut in
            shortcut.name.localizedCaseInsensitiveContains(query) ||
                shortcut.slug.localizedCaseInsensitiveContains(query) ||
                shortcut.command.localizedCaseInsensitiveContains(query)
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: {
                if !$0 {
                    pendingDelete = nil
                }
            }
        )
    }

    private func startNew() {
        draft = UserCommandShortcutDraft()
        slugWasEdited = false
        isEditing = true
    }

    private func edit(_ shortcut: UserCommandShortcut) {
        draft = UserCommandShortcutDraft(shortcut: shortcut)
        slugWasEdited = true
        isEditing = true
    }

    private func updateName(_ name: String) {
        draft.name = name
        if !slugWasEdited {
            draft.slug = UserCommandShortcutValidator.slug(from: name)
        }
    }

    private func updateSlug(_ slug: String) {
        slugWasEdited = true
        draft.slug = UserCommandShortcutValidator.slug(from: slug)
    }

    private func save() {
        let result = store.save(draft)
        guard result.canSave else { return }
        cancel()
    }

    private func deletePendingShortcut() {
        guard let pendingDelete else { return }
        store.delete(pendingDelete)
        self.pendingDelete = nil
    }

    private func cancel() {
        draft = UserCommandShortcutDraft()
        slugWasEdited = false
        isEditing = false
    }
}
