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
                    KajiIcon(systemName: "magnifyingglass", size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .accessibilityHidden(true)

                    TextField("Search", text: $searchState.needle)
                        .textFieldStyle(.plain)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fg)
                        .focused($isFieldFocused)
                        .onSubmit { onNavigateNext() }
                        .onChange(of: searchState.needle) {
                            searchState.pushNeedle()
                        }

                    if !searchState.displayText.isEmpty {
                        Text(searchState.displayText)
                            .kajiFont(size: 10)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityLabel("Search results: \(searchState.displayText)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KajiTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(KajiTheme.border, lineWidth: 1)
                )

                Button(action: onNavigatePrevious) {
                    KajiIcon(systemName: "chevron.up", size: 10)
                }
                .buttonStyle(SearchBarButtonStyle())
                .accessibilityLabel("Previous Match")

                Button(action: onNavigateNext) {
                    KajiIcon(systemName: "chevron.down", size: 10)
                }
                .buttonStyle(SearchBarButtonStyle())
                .accessibilityLabel("Next Match")

                Button(action: onClose) {
                    KajiIcon(systemName: "xmark", size: 10)
                }
                .buttonStyle(SearchBarButtonStyle())
                .accessibilityLabel("Close Search")
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(KajiTheme.bg.opacity(0.95))

            Rectangle().fill(KajiTheme.border).frame(height: 1)
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
            .foregroundStyle(KajiTheme.fgMuted)
            .background(configuration.isPressed ? KajiTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
