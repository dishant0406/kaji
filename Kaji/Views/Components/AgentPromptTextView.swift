import AppKit
import SwiftUI

struct AgentPromptTextView: NSViewRepresentable {
    static let minimumHeight: CGFloat = 22
    static let maximumHeight: CGFloat = 112

    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var completionState: AgentComposerCompletionState
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    let onAttach: ([AskAttachment]) -> Void
    let onCompletionMove: (Int) -> Void
    let onCompletionAccept: (Bool) -> Void
    let onCompletionDismiss: () -> Void
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AgentPromptContainerView {
        let view = AgentPromptContainerView()
        view.textView.delegate = context.coordinator
        view.textView.font = typography.nsFont(size: 13)
        view.textView.textColor = NSColor(KajiTheme.fg)
        view.textView.registerForDraggedTypes([.fileURL])
        view.placeholder.stringValue = placeholder
        context.coordinator.view = view
        context.coordinator.updateHandlers()
        context.coordinator.recalculateHeight()
        return view
    }

    func updateNSView(_ view: AgentPromptContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = view
        if view.textView.string != text {
            view.textView.string = text
        }
        view.textView.font = typography.nsFont(size: 13)
        view.textView.textColor = NSColor(KajiTheme.fg)
        view.textView.isEditable = isEnabled
        view.placeholder.stringValue = placeholder
        view.placeholder.isHidden = !text.isEmpty
        context.coordinator.updateHandlers()
        context.coordinator.recalculateHeight()
        if isEnabled, isFocused.wrappedValue {
            view.focusTextView()
        }
    }

    static func dismantleNSView(_ view: AgentPromptContainerView, coordinator: Coordinator) {
        view.textView.delegate = nil
        view.textView.resetHandlers()
        coordinator.view = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentPromptTextView
        weak var view: AgentPromptContainerView?

        init(parent: AgentPromptTextView) {
            self.parent = parent
        }

        func updateHandlers() {
            view?.textView.onSubmit = parent.onSubmit
            view?.textView.onAttach = parent.onAttach
            view?.textView.onCompletionMove = parent.onCompletionMove
            view?.textView.onCompletionAccept = parent.onCompletionAccept
            view?.textView.onCompletionDismiss = parent.onCompletionDismiss
            view?.textView.hasCompletion = parent.completionState.isVisible
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
            guard let view, let textContainer = view.textView.textContainer else { return }
            view.textView.layoutManager?.ensureLayout(for: textContainer)
            let usedHeight = view.textView.layoutManager?.usedRect(for: textContainer).height ?? 0
            let next = min(max(ceil(usedHeight) + 2, AgentPromptTextView.minimumHeight), AgentPromptTextView.maximumHeight)
            view.updateDocumentHeight(max(next, ceil(usedHeight) + 2))
            view.scrollView.hasVerticalScroller = next >= AgentPromptTextView.maximumHeight
            guard abs(parent.height - next) > 0.5 else { return }
            DispatchQueue.main.async { self.parent.height = next }
        }
    }
}

final class AgentPromptContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = AgentPromptNSTextView()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(textView)
        }
    }
}

final class AgentPromptNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onAttach: (([AskAttachment]) -> Void)?
    var onCompletionMove: ((Int) -> Void)?
    var onCompletionAccept: ((Bool) -> Void)?
    var onCompletionDismiss: (() -> Void)?
    var hasCompletion = false

    override func keyDown(with event: NSEvent) {
        if hasCompletion, event.keyCode == 125 {
            onCompletionMove?(1)
            return
        }
        if hasCompletion, event.keyCode == 126 {
            onCompletionMove?(-1)
            return
        }
        if hasCompletion, event.keyCode == 48 {
            onCompletionAccept?(false)
            return
        }
        if hasCompletion, event.keyCode == 36 || event.keyCode == 76 {
            onCompletionAccept?(true)
            return
        }
        if hasCompletion, event.keyCode == 53 {
            onCompletionDismiss?()
            return
        }
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

    func resetHandlers() {
        onSubmit = nil
        onAttach = nil
        onCompletionMove = nil
        onCompletionAccept = nil
        onCompletionDismiss = nil
    }

    private func attach(from pasteboard: NSPasteboard) -> Bool {
        let attachments = AskAttachmentLoader.attachments(from: pasteboard)
        guard !attachments.isEmpty else { return false }
        onAttach?(attachments)
        return true
    }
}
