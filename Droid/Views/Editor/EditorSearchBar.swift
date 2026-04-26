import SwiftUI

struct EditorSearchBar: View {
    @Bindable var state: EditorTabState
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    private var displayText: String {
        guard !state.searchNeedle.isEmpty else { return "" }
        if state.searchUseRegex, state.searchInvalidRegex { return "Invalid regex" }
        guard state.searchMatchCount > 0 else { return "No results" }
        return "\(state.searchCurrentIndex) of \(state.searchMatchCount)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Button {
                    state.replaceVisible.toggle()
                } label: {
                    DroidIcon(systemName: state.replaceVisible ? "chevron.down" : "chevron.right", size: 10)
                }
                .buttonStyle(EditorSearchButtonStyle())
                .help(state.replaceVisible ? "Hide Replace" : "Show Replace")
                .accessibilityLabel(state.replaceVisible ? "Hide Replace" : "Show Replace")
                .padding(.top, 1)

                VStack(spacing: 4) {
                    searchRow
                    if state.replaceVisible {
                        replaceRow
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DroidTheme.bg.opacity(0.95))

            Rectangle().fill(DroidTheme.border).frame(height: 1)
        }
        .deferFocus($isFieldFocused, on: state.searchFocusVersion)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                DroidIcon(systemName: "magnifyingglass", size: 11)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .accessibilityHidden(true)

                TextField("Search", text: $state.searchNeedle)
                    .textFieldStyle(.plain)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fg)
                    .focused($isFieldFocused)
                    .onSubmit { onNext() }

                if !displayText.isEmpty {
                    Text(displayText)
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgMuted)
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
            .background(DroidTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DroidTheme.border, lineWidth: 1)
            )

            Button(action: onPrevious) {
                DroidIcon(systemName: "chevron.up", size: 10)
            }
            .buttonStyle(EditorSearchButtonStyle())
            .accessibilityLabel("Previous Match")

            Button(action: onNext) {
                DroidIcon(systemName: "chevron.down", size: 10)
            }
            .buttonStyle(EditorSearchButtonStyle())
            .accessibilityLabel("Next Match")

            Button(action: onClose) {
                DroidIcon(systemName: "xmark", size: 10)
            }
            .buttonStyle(EditorSearchButtonStyle())
            .accessibilityLabel("Close Search")
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                DroidIcon(systemName: "arrow.2.squarepath", size: 11)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .accessibilityHidden(true)

                TextField("Replace", text: $state.replaceText)
                    .textFieldStyle(.plain)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fg)
                    .onSubmit(onReplace)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DroidTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DroidTheme.border, lineWidth: 1)
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

private struct EditorSearchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .foregroundStyle(DroidTheme.fgMuted)
            .background(configuration.isPressed ? DroidTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct EditorSearchTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .droidFont(size: 11, weight: .medium)
            .foregroundStyle(isEnabled ? DroidTheme.fg : DroidTheme.fgDim)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(configuration.isPressed ? DroidTheme.surface : DroidTheme.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(DroidTheme.border, lineWidth: 1)
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
                .droidFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(isOn ? DroidTheme.fg : DroidTheme.fgMuted)
                .frame(width: 20, height: 18)
                .background(isOn ? DroidTheme.border : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(isOn ? "Enabled" : "Disabled")
        .accessibilityAddTraits(.isToggle)
    }
}
