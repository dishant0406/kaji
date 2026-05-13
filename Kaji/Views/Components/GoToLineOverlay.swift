import SwiftUI

struct GoToLineOverlay: View {
    let currentLine: Int
    let maxLine: Int
    let onSelect: (EditorLineNavigationRequest) -> Void
    let onDismiss: () -> Void

    @State private var query = ""

    var body: some View {
        ZStack {
            KajiTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField
                Divider().overlay(KajiTheme.border.opacity(0.75))
                preview
            }
            .frame(width: 420, height: 164)
            .background(KajiTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.modalRadius).stroke(KajiTheme.borderStrong.opacity(0.82), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: "number", size: 12)
                .foregroundStyle(KajiTheme.fgDim)
            PaletteSearchField(
                text: $query,
                placeholder: "Go to line:column",
                fontSize: 14,
                onSubmit: confirm,
                onEscape: onDismiss,
                onArrowUp: {},
                onArrowDown: {}
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var preview: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: request == nil ? "arrow.turn.down.right" : "arrow.right.circle", size: 13)
                .foregroundStyle(request == nil ? KajiTheme.fgDim : KajiTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(previewTitle)
                    .kajiFont(size: 13, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text("Current line \(currentLine) of \(maxLine)")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
            Text("Enter")
                .kajiFont(size: 10, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(14)
    }

    private var request: EditorLineNavigationRequest? {
        GoToLineParser.parse(query)
    }

    private var previewTitle: String {
        guard let request else { return "Type a line number, like 120 or 120:8" }
        let line = min(max(1, request.line), maxLine)
        return "Go to line \(line), column \(request.column)"
    }

    private func confirm() {
        guard let request else { return }
        onSelect(request)
    }
}
