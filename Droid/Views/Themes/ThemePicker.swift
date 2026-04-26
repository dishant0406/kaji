import SwiftUI

struct ThemePicker: View {
    @Environment(ThemeService.self) private var themeService
    var onRequestCreate: () -> Void = {}
    var onDismiss: () -> Void = {}
    @State private var themes: [ThemePreview] = []
    @State private var currentThemeIdentifier: String?
    @State private var query = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(spacing: 0) {
            ThemePickerToolbar(
                query: $query,
                onImport: importThemes,
                onCreate: requestThemeCreation
            )
            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)
            if filteredThemes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredThemes) { theme in
                            ThemePickerRow(
                                theme: theme,
                                isActive: theme.identifier == currentThemeIdentifier,
                                onSelect: { selectTheme(theme) },
                                onExport: { exportTheme(theme) }
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            if let statusMessage {
                Rectangle()
                    .fill(DroidTheme.border)
                    .frame(height: 1)
                HStack {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(statusIsError ? DroidTheme.diffRemoveFg : DroidTheme.fgDim)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 360, height: 320)
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.62,
                gradientOpacity: 0.04
            )
        )
        .task { await refreshThemes() }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            Task { await refreshThemes() }
        }
    }

    private var filteredThemes: [ThemePreview] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return themes }
        return themes.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.identifier.localizedCaseInsensitiveContains(trimmed)
        }
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

    private func refreshThemes() async {
        themes = await themeService.loadThemes()
        currentThemeIdentifier = themeService.currentThemeIdentifier()
    }

    private func selectTheme(_ theme: ThemePreview) {
        currentThemeIdentifier = theme.identifier
        themeService.applyTheme(theme.identifier)
    }

    private func requestThemeCreation() {
        onDismiss()
        onRequestCreate()
    }

    private func importThemes() {
        do {
            let imported = try themeService.importThemes()
            statusIsError = false
            statusMessage = imported == 1 ? "Imported 1 theme." : "Imported \(imported) themes."
            Task { await refreshThemes() }
        } catch ThemeServiceError.importCancelled {
            return
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    private func exportTheme(_ theme: ThemePreview) {
        do {
            try themeService.exportTheme(theme)
            statusIsError = false
            statusMessage = "Exported \(theme.name)."
        } catch ThemeServiceError.saveCancelled {
            return
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
