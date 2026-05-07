import SwiftUI

struct DroidCodeGraphNodeRow: View {
    let node: DroidCodeGraphNode
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(DroidCodeGraphPalette.color(for: node.community))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.label)
                    .droidFont(size: 11, weight: selected ? .semibold : .medium)
                    .foregroundStyle(selected ? DroidTheme.fg : DroidTheme.fgMuted)
                    .lineLimit(1)
                Text(node.sourceFile ?? node.fileType)
                    .droidFont(size: 10, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Text("\(node.degree)")
                .droidFont(size: 10, design: .monospaced)
                .foregroundStyle(DroidTheme.fgDim)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(selected ? DroidTheme.surface : .clear, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
    }
}
