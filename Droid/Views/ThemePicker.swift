import SwiftUI

struct ThemePicker: View {
    @Environment(ThemeService.self) private var themeService
    @State private var themes: [ThemePreview] = []
    @State private var currentTheme: String?
    @State private var query = ""
    @State private var hoveredThemeID: String?

    var body: some View {
        VStack(spacing: 0) {
            ThemePickerSearchField(text: $query)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)

            if filteredThemes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredThemes.enumerated()), id: \.element.id) { index, theme in
                            Button {
                                selectTheme(theme)
                            } label: {
                                ThemeRow(
                                    theme: theme,
                                    isActive: theme.name == currentTheme,
                                    isHovered: hoveredThemeID == theme.id
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                hoveredThemeID = isHovering ? theme.id : nil
                            }

                            if index < filteredThemes.count - 1 {
                                Rectangle()
                                    .fill(DroidTheme.border)
                                    .frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 320, height: 300)
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.62,
                gradientOpacity: 0.06
            )
        )
        .task {
            themes = await themeService.loadThemes()
            currentTheme = themeService.currentThemeName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            currentTheme = themeService.currentThemeName()
        }
    }

    private var filteredThemes: [ThemePreview] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return themes }
        return themes.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("No themes found")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DroidTheme.fgMuted)
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Try a different name.")
                    .font(.system(size: 11))
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectTheme(_ theme: ThemePreview) {
        currentTheme = theme.name
        themeService.applyTheme(theme.name)
    }
}

private struct ThemePickerSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            DroidIcon(systemName: "magnifyingglass", size: 12)
                .foregroundStyle(isFocused ? DroidTheme.fgMuted : DroidTheme.fgDim)

            TextField(
                "",
                text: $text,
                prompt: Text("Search themes").foregroundStyle(DroidTheme.fgDim)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(DroidTheme.fg)
            .focused($isFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DroidTheme.secondaryBackground.opacity(0.44), in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .stroke(isFocused ? DroidTheme.borderStrong : DroidTheme.border, lineWidth: 1)
        )
    }
}

private struct ThemeRow: View {
    let theme: ThemePreview
    let isActive: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isActive ? DroidTheme.accent : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.name)
                            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                            .foregroundStyle(DroidTheme.fg)
                            .lineLimit(1)

                        Text(theme.source == .bundled ? "Bundled" : "External")
                            .font(.system(size: 10))
                            .foregroundStyle(DroidTheme.fgDim)
                    }

                    Spacer(minLength: 0)

                    if isActive {
                        DroidIcon(systemName: "checkmark", size: 10)
                            .foregroundStyle(DroidTheme.accent)
                            .padding(.top, 1)
                    }
                }

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(nsColor: theme.background))
                        .overlay(
                            Text("Aa")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(nsColor: theme.foreground))
                        )
                        .frame(width: 26)

                    ForEach(Array(theme.palette.enumerated()), id: \.offset) { _, color in
                        Rectangle()
                            .fill(Color(nsColor: color))
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(DroidTheme.border, lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(rowBackground)
    }

    private var rowBackground: Color {
        if isActive { return DroidTheme.secondaryBackground }
        if isHovered { return DroidTheme.hover }
        return DroidTheme.bg.opacity(0.18)
    }
}
