import SwiftUI

struct CreateThemeModal: View {
    let onFinish: () -> Void
    @State private var themeService = ThemeService.shared
    @State private var draft = ThemeDraft.kajiDefaults
    @State private var inProgress = false
    @State private var errorMessage: String?
    @State private var slugEdited = false
    @State private var syncingSlug = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
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
                        Rectangle().fill(KajiTheme.border).frame(height: 1)
                        Text(errorMessage)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.diffRemoveFg)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                }
                .background(KajiTheme.bg.opacity(0.34))
            }
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            footer
        }
        .frame(width: 640, height: 620)
        .background(
            TranslucentSurface(
                base: KajiTheme.tertiaryBackground,
                material: .hudWindow,
                tintOpacity: 0.66,
                gradientOpacity: 0.08
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.modalRadius)
                .stroke(KajiTheme.border, lineWidth: 1)
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
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Theme Modal") { onFinish() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
    }

    private var footer: some View {
        let createEnabled = ThemeFileCodec.normalizedDraft(draft) != nil && !inProgress
        return HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onFinish)
                .buttonStyle(KajiButtonStyle(.secondary))
            Button(action: createTheme) {
                HStack(spacing: 6) {
                    if inProgress {
                        KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.bg)
                    }
                    Text(inProgress ? "Creating..." : "Create")
                }
            }
            .buttonStyle(KajiButtonStyle(.primary))
            .opacity(createEnabled ? 1 : 0.42)
            .disabled(!createEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
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
