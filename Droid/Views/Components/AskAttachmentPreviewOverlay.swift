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
            .background(DroidTheme.bg, in: RoundedRectangle(cornerRadius: DroidShape.modalRadius))
            .overlay(RoundedRectangle(cornerRadius: DroidShape.modalRadius).stroke(DroidTheme.border, lineWidth: 1))
        }
    }

    private var header: some View {
        HStack {
            Text(attachment.name)
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(DroidTheme.fg)
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
                DroidIcon(systemName: iconName, size: 36)
                    .foregroundStyle(DroidTheme.fgMuted)
                Text(attachment.kind.rawValue.capitalized)
                    .droidFont(size: 13, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                Text(attachment.url.path)
                    .droidFont(size: 11, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgDim)
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
