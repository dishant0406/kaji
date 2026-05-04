import AppKit
import SwiftUI

struct ParentAgentPromptTextView: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    let onAttach: ([AskAttachment]) -> Void
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ParentAgentPromptNSTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onAttach = onAttach
        textView.placeholder = placeholder
        textView.font = typography.nsFont(size: 13)
        textView.textColor = NSColor(DroidTheme.fg)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.registerForDraggedTypes([.fileURL])

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView

        DispatchQueue.main.async {
            if isFocused.wrappedValue {
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ParentAgentPromptNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSubmit = onSubmit
        textView.onAttach = onAttach
        textView.placeholder = placeholder
        textView.font = typography.nsFont(size: 13)
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        if isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ParentAgentPromptTextView

        init(parent: ParentAgentPromptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class ParentAgentPromptNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onAttach: (([AskAttachment]) -> Void)?
    var placeholder = ""

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.keyCode == 9, attach(from: .general) {
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36, flags != .shift {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if attach(from: .general) { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        AskAttachmentLoader.attachments(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        attach(from: sender.draggingPasteboard)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(DroidTheme.fgDim),
        ]
        placeholder.draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height), withAttributes: attributes)
    }

    private func attach(from pasteboard: NSPasteboard) -> Bool {
        let attachments = AskAttachmentLoader.attachments(from: pasteboard)
        guard !attachments.isEmpty else { return false }
        onAttach?(attachments)
        return true
    }
}
