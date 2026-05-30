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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if attachment.kind == .image, let image = NSImage(contentsOf: attachment.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            } else {
                KajiIcon(systemName: iconName, size: 16)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 28, height: 28)
            }
            Text(attachment.name)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
            IconButton(symbol: "xmark", size: 10, accessibilityLabel: "Remove Attachment") {
                onRemove(attachment)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border, lineWidth: 1))
        .onTapGesture { onPreview(attachment) }
        .transition(KajiMotion.disclosureTransition(reduceMotion: reduceMotion))
        .kajiChangeFeedback(KajiMotion.tapFeedback, value: attachment.id)
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
