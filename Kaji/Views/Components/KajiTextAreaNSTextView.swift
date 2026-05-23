import AppKit

final class KajiTextAreaNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onShiftEnter: (() -> Void)?
    var onCommandEnter: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags
        if flags.contains(.command), let onCommandEnter {
            onCommandEnter()
            return
        }
        if flags.contains(.shift), let onShiftEnter {
            onShiftEnter()
            return
        }
        if !flags.contains(.shift), let onSubmit {
            onSubmit()
            return
        }
        super.keyDown(with: event)
    }
}
