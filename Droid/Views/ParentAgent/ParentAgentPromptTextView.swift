import AppKit
import SwiftUI

struct ParentAgentPromptTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    let onAttach: ([AskAttachment]) -> Void
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = ParentAgentPromptNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = typography.nsFont(size: 13)
        field.textColor = NSColor(DroidTheme.fg)
        field.placeholderString = placeholder
        field.cell?.sendsActionOnEndEditing = false
        field.onSubmit = onSubmit
        field.onAttach = onAttach
        field.registerForDraggedTypes([.fileURL])
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.font = typography.nsFont(size: 13)
        field.textColor = NSColor(DroidTheme.fg)
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        if let field = field as? ParentAgentPromptNSTextField {
            field.onSubmit = onSubmit
            field.onAttach = onAttach
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ParentAgentPromptTextView

        init(parent: ParentAgentPromptTextView) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            parent.text = field.stringValue
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

private final class ParentAgentPromptNSTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onAttach: (([AskAttachment]) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 9, attach(from: .general) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        AskAttachmentLoader.attachments(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        attach(from: sender.draggingPasteboard)
    }

    private func attach(from pasteboard: NSPasteboard) -> Bool {
        let attachments = AskAttachmentLoader.attachments(from: pasteboard)
        guard !attachments.isEmpty else { return false }
        onAttach?(attachments)
        return true
    }
}
