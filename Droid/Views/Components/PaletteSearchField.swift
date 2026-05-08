import AppKit
import SwiftUI

struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 13
    let onSubmit: () -> Void
    var onSubmitText: ((String) -> Void)?
    var onShiftSubmitText: ((String) -> Void)?
    var onSpace: (() -> Bool)?
    let onEscape: () -> Void
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    var onPaste: (() -> Bool)?
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = PaletteNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = typography.nsFont(size: fontSize)
        field.textColor = NSColor(DroidTheme.fg)
        field.placeholderString = placeholder
        field.cell?.sendsActionOnEndEditing = false
        field.onEscape = onEscape
        field.onPaste = onPaste
        field.onSpace = onSpace
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = typography.nsFont(size: fontSize)
        if let field = nsView as? PaletteNSTextField {
            field.onEscape = onEscape
            field.onPaste = onPaste
            field.onSpace = onSpace
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField

        init(parent: PaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if let field = control as? NSTextField {
                parent.text = field.stringValue
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
                       let onShiftSubmitText = parent.onShiftSubmitText
                    {
                        onShiftSubmitText(field.stringValue)
                    } else if let onSubmitText = parent.onSubmitText {
                        onSubmitText(field.stringValue)
                    } else {
                        parent.onSubmit()
                    }
                }
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            }
            return false
        }
    }
}

private final class PaletteNSTextField: NSTextField {
    var onEscape: (() -> Void)?
    var onPaste: (() -> Bool)?
    var onSpace: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, onSpace?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 9, onPaste?() == true {
            return true
        }
        if event.keyCode == 53 {
            onEscape?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
