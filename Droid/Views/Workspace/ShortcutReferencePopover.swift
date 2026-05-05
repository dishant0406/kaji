import SwiftUI

struct ShortcutReferencePopover: View {
    @State private var keyBindings = KeyBindingStore.shared
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            DroidInput(
                placeholder: "Search shortcuts",
                text: $searchText,
                leadingIcon: "magnifyingglass"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !filteredKeyboardGroups.isEmpty {
                        keyboardSection
                    }
                    if !filteredKeyboardGroups.isEmpty, !filteredCommandKReferences.isEmpty {
                        Divider().overlay(DroidTheme.border.opacity(0.8))
                    }
                    if !filteredCommandKReferences.isEmpty {
                        commandKSection
                    }
                }
                .padding(.trailing, 4)
            }
            .scrollIndicators(.never)
        }
        .padding(12)
        .frame(width: 360, height: 460)
    }

    private var header: some View {
        HStack(spacing: 8) {
            DroidIcon(systemName: "keyboard", size: 13)
                .foregroundStyle(DroidTheme.fg)
            Text("Shortcuts")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            ShortcutBadge(label: keyBindings.combo(for: .ask).displayString, compact: true)
        }
    }

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Keyboard")
            ForEach(filteredKeyboardGroups) { group in
                ShortcutReferenceGroupView(group: group, keyBindings: keyBindings)
            }
        }
    }

    private var commandKSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Cmd+K")
            ForEach(filteredCommandKReferences) { item in
                HStack(spacing: 10) {
                    ShortcutBadge(label: item.token, compact: true)
                        .frame(width: 82, alignment: .leading)
                    Text(item.detail)
                        .droidFont(size: 11)
                        .foregroundStyle(DroidTheme.fgMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .droidFont(size: 10, weight: .semibold)
            .foregroundStyle(DroidTheme.fgDim)
            .textCase(.uppercase)
    }

    private var filteredKeyboardGroups: [ShortcutReferenceGroup] {
        let query = normalizedSearch
        guard !query.isEmpty else { return ShortcutReferenceCatalog.keyboardGroups }
        return ShortcutReferenceCatalog.keyboardGroups.compactMap { group in
            let actions = group.actions.filter { action in
                action.displayName.localizedCaseInsensitiveContains(query) ||
                    group.title.localizedCaseInsensitiveContains(query) ||
                    keyBindings.combo(for: action).displayString.localizedCaseInsensitiveContains(query)
            }
            guard !actions.isEmpty else { return nil }
            return ShortcutReferenceGroup(title: group.title, actions: actions)
        }
    }

    private var filteredCommandKReferences: [CommandKReference] {
        let query = normalizedSearch
        guard !query.isEmpty else { return ShortcutReferenceCatalog.commandKReferences }
        return ShortcutReferenceCatalog.commandKReferences.filter {
            $0.token.localizedCaseInsensitiveContains(query) ||
                $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ShortcutReferenceGroupView: View {
    let group: ShortcutReferenceGroup
    let keyBindings: KeyBindingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(group.title)
                .droidFont(size: 10, weight: .semibold)
                .foregroundStyle(DroidTheme.fgDim)

            ForEach(group.actions) { action in
                HStack(spacing: 10) {
                    Text(action.displayName)
                        .droidFont(size: 11)
                        .foregroundStyle(DroidTheme.fgMuted)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    ShortcutBadge(label: keyBindings.combo(for: action).displayString, compact: true)
                }
            }
        }
    }
}
