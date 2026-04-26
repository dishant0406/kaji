import SwiftUI

struct CreateThemeModal: View {
    let onFinish: () -> Void
    @State private var themeService = ThemeService.shared
    @State private var draft = ThemeDraft.droidDefaults
    @State private var inProgress = false
    @State private var errorMessage: String?
    @State private var slugEdited = false
    @State private var syncingSlug = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ThemeFormSection("Theme") {
                        ThemeColorFieldGrid(rows: basicRows)
                    }
                    ThemeFormSection("Core colors") {
                        ThemeColorFieldGrid(rows: colorRows)
                    }
                    ThemeFormSection("Palette", showsDivider: errorMessage == nil) {
                        ThemePaletteGrid(colors: paletteBindings)
                    }
                    if let errorMessage {
                        Rectangle().fill(DroidTheme.border).frame(height: 1)
                        Text(errorMessage)
                            .droidFont(size: 11)
                            .foregroundStyle(DroidTheme.diffRemoveFg)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                }
                .background(DroidTheme.bg.opacity(0.34))
            }
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            footer
        }
        .frame(width: 640, height: 620)
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .hudWindow,
                tintOpacity: 0.66,
                gradientOpacity: 0.08
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                .stroke(DroidTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .task {
            draft = themeService.prepareDraft()
        }
        .onChange(of: draft.name) { _, newValue in
            guard !slugEdited else { return }
            syncingSlug = true
            draft.slug = themeService.suggestedSlug(for: newValue)
            syncingSlug = false
        }
        .onChange(of: draft.slug) { _, _ in
            if !syncingSlug {
                slugEdited = true
            }
        }
    }

    private var basicRows: [ThemeColorFieldGrid.Row] {
        [
            .init(label: "Name", binding: $draft.name, placeholder: "Noir Terminal", monospaced: false),
            .init(label: "Slug", binding: $draft.slug, placeholder: "noir-terminal", monospaced: true),
        ]
    }

    private var colorRows: [ThemeColorFieldGrid.Row] {
        [
            .init(label: "Background", binding: binding(\.background), placeholder: "#0F1419"),
            .init(label: "Foreground", binding: binding(\.foreground), placeholder: "#E6E1CF"),
            .init(label: "Cursor", binding: binding(\.cursorColor), placeholder: "#E6B450"),
            .init(label: "Cursor text", binding: binding(\.cursorText), placeholder: "#0F1419"),
            .init(label: "Selection", binding: binding(\.selectionBackground), placeholder: "#273747"),
            .init(label: "Selection text", binding: binding(\.selectionForeground), placeholder: "#E6E1CF"),
        ]
    }

    private var paletteBindings: [Binding<String>] {
        draft.colors.palette.indices.map { index in
            Binding(
                get: { draft.colors.palette[index] },
                set: { draft.colors.palette[index] = $0 }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("New Theme")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Theme Modal") { onFinish() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var footer: some View {
        let createEnabled = ThemeFileCodec.normalizedDraft(draft) != nil && !inProgress
        return HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onFinish)
                .buttonStyle(DroidButtonStyle(.secondary))
            Button(action: createTheme) {
                HStack(spacing: 6) {
                    if inProgress {
                        DroidSpinner(size: 11, lineWidth: 1.4, color: DroidTheme.bg)
                    }
                    Text(inProgress ? "Creating..." : "Create")
                }
            }
            .buttonStyle(DroidButtonStyle(.primary))
            .opacity(createEnabled ? 1 : 0.42)
            .disabled(!createEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private func binding(_ keyPath: WritableKeyPath<ThemeColorSet, String>) -> Binding<String> {
        Binding(
            get: { draft.colors[keyPath: keyPath] },
            set: { draft.colors[keyPath: keyPath] = $0 }
        )
    }

    private func createTheme() {
        inProgress = true
        errorMessage = nil
        do {
            _ = try themeService.createTheme(draft)
            inProgress = false
            onFinish()
        } catch {
            inProgress = false
            errorMessage = error.localizedDescription
        }
    }
}
