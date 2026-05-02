import SwiftUI

struct AskAttachmentStrip: View {
    let attachments: [AskAttachment]
    let onRemove: (AskAttachment) -> Void
    let onPreview: (AskAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AskAttachmentThumbnail(attachment: attachment, onRemove: onRemove, onPreview: onPreview)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

private struct AskAttachmentThumbnail: View {
    let attachment: AskAttachment
    let onRemove: (AskAttachment) -> Void
    let onPreview: (AskAttachment) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if attachment.kind == .image, let image = NSImage(contentsOf: attachment.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            } else {
                DroidIcon(systemName: iconName, size: 16)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .frame(width: 28, height: 28)
            }
            Text(attachment.name)
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgMuted)
                .lineLimit(1)
            IconButton(symbol: "xmark", size: 10, accessibilityLabel: "Remove Attachment") {
                onRemove(attachment)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: DroidShape.tileRadius).stroke(DroidTheme.border, lineWidth: 1))
        .onTapGesture { onPreview(attachment) }
    }

    private var iconName: String {
        switch attachment.kind {
        case .folder: "folder"
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .archive: "archivebox"
        case .file: "doc"
        }
    }
}
