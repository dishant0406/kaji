import SwiftUI

struct ProblemsPanel: View {
    @Bindable var store: DiagnosticsStore
    let onOpenDiagnostic: (EditorDiagnostic) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            content
        }
        .background(KajiTheme.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Problems")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            countBadge("\(store.errorCount)", color: KajiTheme.diffRemoveFg)
            countBadge("\(store.warningCount)", color: KajiTheme.diffHunkFg)
            Button(action: onClose) {
                KajiIcon(systemName: "xmark", size: 10)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Problems")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var content: some View {
        Group {
            if store.groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(store.groups) { group in
                            ProblemFileGroupView(group: group, onOpenDiagnostic: onOpenDiagnostic)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            KajiIcon(systemName: "checkmark.circle", size: 18)
                .foregroundStyle(KajiTheme.diffAddFg)
            Text("No problems detected")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countBadge(_ value: String, color: Color) -> some View {
        Text(value)
            .kajiFont(size: 10, design: .monospaced)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ProblemFileGroupView: View {
    let group: EditorDiagnosticFileGroup
    let onOpenDiagnostic: (EditorDiagnostic) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                KajiIcon(systemName: "doc.text", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 14)
                Text(group.relativePath)
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(group.diagnostics.count)")
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)

            ForEach(group.diagnostics) { diagnostic in
                ProblemRow(diagnostic: diagnostic, onOpen: { onOpenDiagnostic(diagnostic) })
            }
        }
        .padding(6)
        .background(KajiTheme.chrome.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProblemRow: View {
    let diagnostic: EditorDiagnostic
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KajiIcon(systemName: icon, size: 10)
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(diagnostic.message)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(2)
                Text(locationText)
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(hovered ? KajiTheme.secondaryBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onOpen)
    }

    private var locationText: String {
        let source = diagnostic.source.map { " • \($0)" } ?? ""
        return "\(diagnostic.line):\(diagnostic.column)\(source)"
    }

    private var icon: String {
        switch diagnostic.severity {
        case .error: "xmark.circle"
        case .warning: "exclamationmark.triangle"
        case .information: "info.circle"
        case .hint: "lightbulb"
        }
    }

    private var color: Color {
        switch diagnostic.severity {
        case .error: KajiTheme.diffRemoveFg
        case .warning: KajiTheme.diffHunkFg
        case .information: KajiTheme.accent
        case .hint: KajiTheme.fgDim
        }
    }
}
