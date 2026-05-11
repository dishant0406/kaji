import SwiftUI

struct KajiCodeGraphNodeRow: View {
    let node: KajiCodeGraphNode
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(KajiCodeGraphPalette.color(for: node.community))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.label)
                    .kajiFont(size: 11, weight: selected ? .semibold : .medium)
                    .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                    .lineLimit(1)
                Text(node.sourceFile ?? node.fileType)
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Text("\(node.degree)")
                .kajiFont(size: 10, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(selected ? KajiTheme.surface : .clear, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }
}
