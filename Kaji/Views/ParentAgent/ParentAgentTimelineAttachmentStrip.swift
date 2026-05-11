import SwiftUI

struct ParentAgentTimelineAttachmentStrip: View {
    let attachments: [ParentAgentAttachmentContext]
    let onPreview: (AskAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.path) { attachment in
                    ParentAgentTimelineAttachmentTile(attachment: attachment, onPreview: onPreview)
                }
            }
        }
    }
}

private struct ParentAgentTimelineAttachmentTile: View {
    let attachment: ParentAgentAttachmentContext
    let onPreview: (AskAttachment) -> Void

    var body: some View {
        HStack(spacing: 7) {
            preview
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .kajiFont(size: 11, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(attachment.kind.capitalized)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border, lineWidth: 1))
        .onTapGesture { onPreview(AskAttachment(url: URL(fileURLWithPath: attachment.path))) }
    }

    @ViewBuilder
    private var preview: some View {
        if attachment.kind == "image", let image = NSImage(contentsOfFile: attachment.path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        } else {
            KajiIcon(systemName: iconName, size: 15)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 30, height: 30)
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case "folder": "folder"
        case "image": "photo"
        case "pdf": "doc.richtext"
        case "text": "doc.text"
        case "archive": "archivebox"
        default: "doc"
        }
    }
}
