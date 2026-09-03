import SwiftUI

struct EditorSearchBar: View {
    @Bindable var state: EditorTabState
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var focusedField: EditorSearchFocusedField?

    private var displayText: String {
        guard !state.searchNeedle.isEmpty else { return "" }
        if state.searchUseRegex, state.searchInvalidRegex {
            return "Invalid regex"
        }
        guard state.searchMatchCount > 0 else { return "No results" }
        return "\(state.searchCurrentIndex) of \(state.searchMatchCount)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Button {
                    state.replaceVisible.toggle()
                } label: {
                    KajiIcon(systemName: state.replaceVisible ? "chevron.down" : "chevron.right", size: 10)
                }
                .buttonStyle(EditorSearchButtonStyle())
                .help(state.replaceVisible ? "Hide Replace" : "Show Replace")
                .accessibilityLabel(state.replaceVisible ? "Hide Replace" : "Show Replace")
                .padding(.top, 1)

                VStack(spacing: 4) {
                    searchRow
                    if state.replaceVisible {
                        replaceRow
                            .transition(KajiMotion.disclosureTransition(reduceMotion: false))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(KajiTheme.bg.opacity(0.95))

            Rectangle().fill(KajiTheme.border).frame(height: 1)
        }
        .onChange(of: state.searchFocusVersion) { _, _ in focusedField = .search }
        .onChange(of: state.replaceFocusVersion) { _, _ in focusedField = .replace }
        .onAppear { focusedField = state.replaceVisible ? .replace : .search }
        .animation(KajiMotion.panel, value: state.replaceVisible)
        .attachedShortcutHint(label: "Enter", modifiers: 0, placement: .topTrailing, showWhenAnyModifierHeld: true)
        .attachedShortcutHint(label: "Esc", modifiers: 0, placement: .bottomTrailing, showWhenAnyModifierHeld: true)
        .attachedShortcutHint(label: "⇧Enter", modifiers: KeyCombo(key: "x", shift: true).modifiers, placement: .bottomLeading)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                KajiIcon(systemName: "magnifyingglass", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .accessibilityHidden(true)

                TextField("Search", text: $state.searchNeedle)
                    .textFieldStyle(.plain)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fg)
                    .focused($focusedField, equals: .search)
                    .onSubmit { onNext() }
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            onPrevious()
                        } else {
                            onNext()
                        }
                        return .handled
                    }

                if !displayText.isEmpty {
                    Text(displayText)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(1)
                        .fixedSize()
                }

                EditorSearchOptionToggle(
                    label: "Aa",
                    isOn: $state.searchCaseSensitive,
                    help: "Match Case"
                )

                EditorSearchOptionToggle(
                    label: ".*",
                    isOn: $state.searchUseRegex,
                    help: "Regular Expression"
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KajiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(KajiTheme.border, lineWidth: 1)
            )

            Button(action: onPrevious) {
                KajiIcon(systemName: "chevron.up", size: 10)
            }
            .buttonStyle(EditorSearchButtonStyle())
            .accessibilityLabel("Previous Match")

            Button(action: onNext) {
                KajiIcon(systemName: "chevron.down", size: 10)
            }
            .buttonStyle(EditorSearchButtonStyle())
            .accessibilityLabel("Next Match")

            Button(action: onClose) {
                KajiIcon(systemName: "xmark", size: 10)
            }
            .buttonStyle(EditorSearchButtonStyle())
            .accessibilityLabel("Close Search")
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                KajiIcon(systemName: "arrow.2.squarepath", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .accessibilityHidden(true)

                TextField("Replace", text: $state.replaceText)
                    .textFieldStyle(.plain)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fg)
                    .focused($focusedField, equals: .replace)
                    .onSubmit(onReplace)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KajiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(KajiTheme.border, lineWidth: 1)
            )

            Button("Replace", action: onReplace)
                .buttonStyle(EditorSearchTextButtonStyle())
                .disabled(state.searchMatchCount == 0)

            Button("All", action: onReplaceAll)
                .buttonStyle(EditorSearchTextButtonStyle())
                .disabled(state.searchMatchCount == 0)
        }
    }
}

private enum EditorSearchFocusedField: Hashable {
    case search
    case replace
}

private struct EditorSearchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .foregroundStyle(KajiTheme.fgMuted)
            .background(configuration.isPressed ? KajiTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct EditorSearchTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kajiFont(size: 11, weight: .medium)
            .foregroundStyle(isEnabled ? KajiTheme.fg : KajiTheme.fgDim)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(configuration.isPressed ? KajiTheme.surface : KajiTheme.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(KajiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct EditorSearchOptionToggle: View {
    let label: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(isOn ? KajiTheme.fg : KajiTheme.fgMuted)
                .frame(width: 20, height: 18)
                .background(isOn ? KajiTheme.border : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(isOn ? "Enabled" : "Disabled")
        .accessibilityAddTraits(.isToggle)
    }
}
