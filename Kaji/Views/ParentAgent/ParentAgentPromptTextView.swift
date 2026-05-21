import AppKit
import SwiftUI

struct ParentAgentPromptTextView: NSViewRepresentable {
    static let minimumHeight: CGFloat = 22
    static let maximumHeight: CGFloat = 112

    @Binding var text: String
    @Binding var height: CGFloat
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    let onAttach: ([AskAttachment]) -> Void
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ParentAgentPromptContainerView {
        let view = ParentAgentPromptContainerView()
        view.textView.delegate = context.coordinator
        view.textView.font = typography.nsFont(size: 13)
        view.textView.textColor = NSColor(KajiTheme.fg)
        view.textView.onSubmit = onSubmit
        view.textView.onAttach = onAttach
        view.textView.registerForDraggedTypes([.fileURL])
        view.placeholder.stringValue = placeholder
        context.coordinator.view = view
        context.coordinator.recalculateHeight()
        return view
    }

    func updateNSView(_ view: ParentAgentPromptContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = view
        if view.textView.string != text {
            view.textView.string = text
        }
        view.textView.font = typography.nsFont(size: 13)
        view.textView.textColor = NSColor(KajiTheme.fg)
        view.textView.isEditable = isEnabled
        view.textView.onSubmit = onSubmit
        view.textView.onAttach = onAttach
        view.placeholder.stringValue = placeholder
        view.placeholder.isHidden = !text.isEmpty
        context.coordinator.recalculateHeight()
        if isEnabled, isFocused.wrappedValue {
            view.focusTextView()
        }
    }

    static func dismantleNSView(_ view: ParentAgentPromptContainerView, coordinator: Coordinator) {
        view.textView.delegate = nil
        view.textView.onSubmit = nil
        view.textView.onAttach = nil
        coordinator.view = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ParentAgentPromptTextView
        weak var view: ParentAgentPromptContainerView?

        init(parent: ParentAgentPromptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            view?.placeholder.isHidden = !textView.string.isEmpty
            recalculateHeight()
        }

        func textDidBeginEditing(_: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func recalculateHeight() {
            guard let view else { return }
            guard let textContainer = view.textView.textContainer else { return }
            view.textView.layoutManager?.ensureLayout(for: textContainer)
            let usedHeight = view.textView.layoutManager?.usedRect(for: textContainer).height ?? 0
            let next = min(
                max(ceil(usedHeight) + 2, ParentAgentPromptTextView.minimumHeight),
                ParentAgentPromptTextView.maximumHeight
            )
            view.updateDocumentHeight(max(next, ceil(usedHeight) + 2))
            view.scrollView.hasVerticalScroller = next >= ParentAgentPromptTextView.maximumHeight
            guard abs(parent.height - next) > 0.5 else { return }
            DispatchQueue.main.async { self.parent.height = next }
        }
    }
}

final class ParentAgentPromptContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = ParentAgentPromptNSTextView()
    let placeholder = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.documentView = textView
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        placeholder.textColor = NSColor(KajiTheme.fgDim)
        placeholder.backgroundColor = .clear
        placeholder.isBordered = false
        placeholder.isEditable = false
        placeholder.isEnabled = false
        placeholder.isSelectable = false
        addSubview(scrollView)
        addSubview(placeholder)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame = NSRect(origin: .zero, size: bounds.size)
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        placeholder.frame = NSRect(x: 0, y: bounds.height - 18, width: bounds.width, height: 18)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === placeholder ? textView : hit
    }

    func updateDocumentHeight(_ height: CGFloat) {
        let documentHeight = max(bounds.height, height)
        textView.frame = NSRect(origin: .zero, size: NSSize(width: bounds.width, height: documentHeight))
    }

    func focusTextView() {
        focusTextView(attemptsRemaining: 12)
    }

    private func focusTextView(attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if window?.firstResponder !== textView {
                window?.makeFirstResponder(textView)
            }
            guard window?.firstResponder !== textView, attemptsRemaining > 0 else { return }
            focusTextView(attemptsRemaining: attemptsRemaining - 1)
        }
    }
}

final class ParentAgentPromptNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onAttach: (([AskAttachment]) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

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
