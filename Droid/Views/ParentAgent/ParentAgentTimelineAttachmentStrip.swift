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
                    .droidFont(size: 11, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                    .lineLimit(1)
                Text(attachment.kind.capitalized)
                    .droidFont(size: 10)
                    .foregroundStyle(DroidTheme.fgDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: DroidShape.tileRadius).stroke(DroidTheme.border, lineWidth: 1))
        .onTapGesture { onPreview(AskAttachment(url: URL(fileURLWithPath: attachment.path))) }
    }

    @ViewBuilder
    private var preview: some View {
        if attachment.kind == "image", let image = NSImage(contentsOfFile: attachment.path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        } else {
            DroidIcon(systemName: iconName, size: 15)
                .foregroundStyle(DroidTheme.fgMuted)
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
