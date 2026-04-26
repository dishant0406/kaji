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
            DroidInput(
                placeholder: "Search shortcuts",
                text: $searchText,
                leadingIcon: "magnifyingglass"
            )

            Button("Reset All") {
                store.resetToDefaults()
                recordingAction = nil
            }
            .buttonStyle(DroidButtonStyle(.secondary, size: .small))
        }
        .padding(SettingsMetrics.horizontalPadding)
    }

    private var shortcutsList: some View {
        let visibleCategories = ShortcutAction.categories.filter { !filteredActions(for: $0).isEmpty }
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(visibleCategories, id: \.self) { category in
                    categorySection(
                        title: category,
                        actions: filteredActions(for: category),
                        isLast: category == visibleCategories.last
                    )
                }
            }
        }
    }

    private func categorySection(title: String, actions: [ShortcutAction], isLast: Bool) -> some View {
        SettingsSection(title, showsDivider: !isLast) {
            ForEach(actions) { action in
                ShortcutRow(
                    action: action,
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

    private func filteredActions(for category: String) -> [ShortcutAction] {
        let actions = ShortcutAction.allCases.filter { $0.category == category }
        guard !searchText.isEmpty else { return actions }
        return actions.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
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

private struct ShortcutRow: View {
    let action: ShortcutAction
    let combo: KeyCombo
    let isRecording: Bool
    let conflictAction: ShortcutAction?
    let onStartRecording: () -> Void
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void
    let onReset: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.displayName)
                    .droidFont(size: SettingsMetrics.labelFontSize)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isRecording {
                    recordingView
                } else {
                    comboDisplay
                }
            }

            if let conflictAction {
                Text("Conflicts with \"\(conflictAction.displayName)\" — press a different shortcut or Esc to cancel")
                    .droidFont(size: 10)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .background(hovered ? DroidTheme.surface : .clear)
        .onHover { hovered = $0 }
    }

    private var comboDisplay: some View {
        HStack(spacing: 6) {
            if hovered {
                Button(action: onReset) {
                    DroidIcon(systemName: "arrow.counterclockwise", size: 10)
                }
                .buttonStyle(DroidButtonStyle(.ghost, size: .small))
                .accessibilityLabel("Reset Shortcut")
            }

            Button(action: onStartRecording) {
                Text(combo.displayString)
                    .droidFont(size: SettingsMetrics.footnoteFontSize, weight: .medium, design: .rounded)
            }
            .buttonStyle(DroidButtonStyle(.secondary, size: .small))
        }
    }

    private var recordingView: some View {
        ZStack {
            ShortcutRecorderView(onRecord: onRecord, onCancel: onCancel)
                .frame(width: 0, height: 0)
                .opacity(0)

            Text("Press shortcut…")
                .droidFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                .foregroundStyle(DroidTheme.diffHunkFg)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DroidTheme.diffHunkBg, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
