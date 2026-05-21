import SwiftUI

struct ShortcutReferencePopover: View {
    @State private var keyBindings = KeyBindingStore.shared
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            KajiInput(
                placeholder: "Search shortcuts",
                text: $searchText,
                leadingIcon: "magnifyingglass"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !filteredKeyboardGroups.isEmpty {
                        keyboardSection
                    }
                    if !filteredKeyboardGroups.isEmpty, !filteredLocalShortcuts.isEmpty {
                        Divider().overlay(KajiTheme.border.opacity(0.8))
                    }
                    if !filteredLocalShortcuts.isEmpty {
                        localShortcutsSection
                    }
                    if !filteredKeyboardGroups.isEmpty || !filteredLocalShortcuts.isEmpty, !filteredCommandKReferences.isEmpty {
                        Divider().overlay(KajiTheme.border.opacity(0.8))
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
            KajiIcon(systemName: "keyboard", size: 13)
                .foregroundStyle(KajiTheme.fg)
            Text("Shortcuts")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
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
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var localShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Contextual")
            ForEach(filteredLocalGroups, id: \.key) { category, shortcuts in
                VStack(alignment: .leading, spacing: 7) {
                    Text(category)
                        .kajiFont(size: 10, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgDim)
                    ForEach(shortcuts) { shortcut in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortcut.name)
                                    .kajiFont(size: 11)
                                    .foregroundStyle(KajiTheme.fgMuted)
                                    .lineLimit(1)
                                Text(shortcut.context)
                                    .kajiFont(size: 10)
                                    .foregroundStyle(KajiTheme.fgDim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 10)
                            ShortcutBadge(label: shortcut.keys, compact: true)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .kajiFont(size: 10, weight: .semibold)
            .foregroundStyle(KajiTheme.fgDim)
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

    private var filteredLocalShortcuts: [LocalShortcutReference] {
        let query = normalizedSearch
        guard !query.isEmpty else { return ShortcutReferenceCatalog.localShortcuts }
        return ShortcutReferenceCatalog.localShortcuts.filter {
            $0.keys.localizedCaseInsensitiveContains(query) ||
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.category.localizedCaseInsensitiveContains(query) ||
                $0.context.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredLocalGroups: [(key: String, value: [LocalShortcutReference])] {
        Dictionary(grouping: filteredLocalShortcuts, by: \.category)
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
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
                .kajiFont(size: 10, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)

            ForEach(group.actions) { action in
                HStack(spacing: 10) {
                    Text(action.displayName)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    ShortcutBadge(label: keyBindings.combo(for: action).displayString, compact: true)
                }
            }
        }
    }
}
