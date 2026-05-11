import AppKit
import SwiftUI

struct AskAttachmentDropTarget: NSViewRepresentable {
    let onDrop: ([AskAttachment]) -> Void

    func makeNSView(context: Context) -> AskAttachmentDropTargetView {
        let view = AskAttachmentDropTargetView()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: AskAttachmentDropTargetView, context: Context) {
        nsView.onDrop = onDrop
    }
}

final class AskAttachmentDropTargetView: NSView {
    var onDrop: (([AskAttachment]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        attachments(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = attachments(from: sender.draggingPasteboard)
        guard !dropped.isEmpty else { return false }
        onDrop?(dropped)
        return true
    }

    private func attachments(from pasteboard: NSPasteboard) -> [AskAttachment] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return urls.map { AskAttachment(url: $0) }
    }
}
