import SwiftUI

struct AskAttachmentPreviewOverlay: View {
    let attachment: AskAttachment
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 10) {
                header
                content
            }
            .padding(12)
            .frame(width: 760, height: 580)
            .background(KajiTheme.bg, in: RoundedRectangle(cornerRadius: KajiShape.modalRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.modalRadius).stroke(KajiTheme.border, lineWidth: 1))
        }
    }

    private var header: some View {
        HStack {
            Text(attachment.name)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Attachment Preview", action: onDismiss)
        }
    }

    @ViewBuilder
    private var content: some View {
        if attachment.kind == .image, let image = NSImage(contentsOf: attachment.url) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 720, maxHeight: 520)
        } else {
            VStack(spacing: 10) {
                KajiIcon(systemName: iconName, size: 36)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text(attachment.kind.rawValue.capitalized)
                    .kajiFont(size: 13, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(attachment.url.path)
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case .folder: "folder"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .archive: "archivebox"
        case .image: "photo"
        case .file: "doc"
        }
    }
}
