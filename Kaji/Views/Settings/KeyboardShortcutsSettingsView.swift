import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    @State private var recordingAction: ShortcutAction?
    @State private var searchText = ""
    @State private var conflictWarning: (action: ShortcutAction, existing: ShortcutAction)?

    private var store: KeyBindingStore { KeyBindingStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            shortcutsList
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiInput(
                placeholder: "Search shortcuts",
                text: $searchText,
                leadingIcon: "magnifyingglass"
            )

            Button("Reset All") {
                store.resetToDefaults()
                recordingAction = nil
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
        .padding(SettingsMetrics.horizontalPadding)
    }

    private var shortcutsList: some View {
        let visibleGroups = filteredGroups
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(visibleGroups) { group in
                    categorySection(
                        title: group.title,
                        actions: group.actions,
                        isLast: false
                    )
                }
                UserCommandShortcutSettingsSection(searchText: searchText)
            }
        }
    }

    private func categorySection(title: String, actions: [ShortcutAction], isLast: Bool) -> some View {
        SettingsSection(title, showsDivider: !isLast) {
            ForEach(actions) { action in
                KeyboardShortcutRow(
                    action: action,
                    displayName: FooterLauncherShortcutResolver.displayName(for: action),
                    combo: store.combo(for: action),
                    isRecording: recordingAction == action,
                    conflictAction: conflictWarning?.action == action ? conflictWarning?.existing : nil,
                    onStartRecording: { recordingAction = action
                        conflictWarning = nil
                    },
                    onRecord: { combo in handleRecord(action: action, combo: combo) },
                    onCancel: { recordingAction = nil
                        conflictWarning = nil
                    },
                    onReset: { store.resetBinding(action: action)
                        conflictWarning = nil
                    }
                )
            }
        }
    }

    private var filteredGroups: [ShortcutReferenceGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ShortcutReferenceCatalog.keyboardGroups }
        return ShortcutReferenceCatalog.keyboardGroups.compactMap { group in
            let actions = group.actions.filter { action in
                (FooterLauncherShortcutResolver.displayName(for: action) ?? action.displayName).localizedCaseInsensitiveContains(query) ||
                    group.title.localizedCaseInsensitiveContains(query) ||
                    store.combo(for: action).displayString.localizedCaseInsensitiveContains(query)
            }
            guard !actions.isEmpty else { return nil }
            return ShortcutReferenceGroup(title: group.title, actions: actions)
        }
    }

    private func handleRecord(action: ShortcutAction, combo: KeyCombo) {
        if let existing = store.conflictingAction(for: combo, excluding: action) {
            conflictWarning = (action: action, existing: existing)
            return
        }
        store.updateBinding(action: action, combo: combo)
        recordingAction = nil
        conflictWarning = nil
    }
}
