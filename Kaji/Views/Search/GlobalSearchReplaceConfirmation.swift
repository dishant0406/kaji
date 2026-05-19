import SwiftUI

struct GlobalSearchReplaceConfirmation: View {
    let preview: ProjectTextReplacePreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                KajiIcon(systemName: "exclamationmark.triangle", size: 13)
                    .foregroundStyle(KajiTheme.diffHunkFg)
                Text("Replace Across Files?")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer()
            }
            Text(summary)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("This writes directly to disk. Open clean editor tabs will reload after the replace finishes.")
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                Button("Replace All", action: onConfirm)
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(maxWidth: 340)
        .background(KajiTheme.bg, in: RoundedRectangle(cornerRadius: KajiShape.modalRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.modalRadius).stroke(KajiTheme.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
    }

    private var summary: String {
        "Replace \(preview.matchCount) match\(preview.matchCount == 1 ? "" : "es") in " +
            "\(preview.fileCount) file\(preview.fileCount == 1 ? "" : "s") with \"\(preview.replacement)\"."
    }
}
