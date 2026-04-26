import SwiftUI

struct TerminalSearchBar: View {
    @Bindable var searchState: TerminalSearchState
    let onNavigateNext: () -> Void
    let onNavigatePrevious: () -> Void
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    DroidIcon(systemName: "magnifyingglass", size: 11)
                        .foregroundStyle(DroidTheme.fgMuted)
                        .accessibilityHidden(true)

                    TextField("Search", text: $searchState.needle)
                        .textFieldStyle(.plain)
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fg)
                        .focused($isFieldFocused)
                        .onSubmit { onNavigateNext() }
                        .onChange(of: searchState.needle) {
                            searchState.pushNeedle()
                        }

                    if !searchState.displayText.isEmpty {
                        Text(searchState.displayText)
                            .droidFont(size: 10)
                            .foregroundStyle(DroidTheme.fgMuted)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityLabel("Search results: \(searchState.displayText)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DroidTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DroidTheme.border, lineWidth: 1)
                )

                Button(action: onNavigatePrevious) {
                    DroidIcon(systemName: "chevron.up", size: 10)
                }
                .buttonStyle(SearchBarButtonStyle())
                .accessibilityLabel("Previous Match")

                Button(action: onNavigateNext) {
                    DroidIcon(systemName: "chevron.down", size: 10)
                }
                .buttonStyle(SearchBarButtonStyle())
                .accessibilityLabel("Next Match")

                Button(action: onClose) {
                    DroidIcon(systemName: "xmark", size: 10)
                }
                .buttonStyle(SearchBarButtonStyle())
                .accessibilityLabel("Close Search")
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(DroidTheme.bg.opacity(0.95))

            Rectangle().fill(DroidTheme.border).frame(height: 1)
        }
        .deferFocus($isFieldFocused, on: searchState.focusVersion)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }
}

private struct SearchBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .foregroundStyle(DroidTheme.fgMuted)
            .background(configuration.isPressed ? DroidTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
