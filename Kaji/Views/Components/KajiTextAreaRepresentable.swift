import AppKit
import SwiftUI

struct KajiTextAreaRepresentable: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var monospaced: Bool
    var onSubmit: (() -> Void)?
    var onShiftEnter: (() -> Void)?
    var onCommandEnter: (() -> Void)?
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> KajiTextAreaContainerView {
        let view = KajiTextAreaContainerView()
        view.textView.delegate = context.coordinator
        context.coordinator.view = view
        apply(to: view)
        return view
    }

    func updateNSView(_ view: KajiTextAreaContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = view
        if view.textView.string != text {
            view.textView.string = text
        }
        apply(to: view)
        view.placeholder.isHidden = !text.isEmpty
        if isFocused {
            view.focusTextView()
        }
    }

    static func dismantleNSView(_ view: KajiTextAreaContainerView, coordinator: Coordinator) {
        view.textView.delegate = nil
        view.textView.onSubmit = nil
        view.textView.onShiftEnter = nil
        view.textView.onCommandEnter = nil
        coordinator.view = nil
    }

    private func apply(to view: KajiTextAreaContainerView) {
        let font = typography.nsFont(size: 12)
        view.textView.font = font
        view.textView.textColor = NSColor(KajiTheme.fg)
        view.textView.onSubmit = onSubmit
        view.textView.onShiftEnter = onShiftEnter
        view.textView.onCommandEnter = onCommandEnter
        view.placeholder.stringValue = placeholder
        view.placeholder.font = font
        view.placeholder.textColor = NSColor(KajiTheme.fgDim)
        view.needsLayout = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KajiTextAreaRepresentable
        weak var view: KajiTextAreaContainerView?

        init(parent: KajiTextAreaRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            view?.placeholder.isHidden = !textView.string.isEmpty
            view?.needsLayout = true
        }

        func textDidBeginEditing(_: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_: Notification) {
            parent.isFocused = false
        }
    }
}
