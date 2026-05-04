import AppKit
import SwiftUI

struct DroidCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let language: DroidCodeLanguage
    var minHeight: CGFloat = 220
    @Environment(AppTypographySettings.self) private var typography

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = DroidCodeTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = typography.nsFont(size: 12)
        textView.backgroundColor = GhosttyService.shared.backgroundColor
        textView.textColor = SyntaxTheme.defaultForeground
        textView.insertionPointColor = SyntaxTheme.defaultForeground
        textView.typingAttributes = [
            .font: typography.nsFont(size: 12),
            .foregroundColor: SyntaxTheme.defaultForeground,
        ]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        scrollView.verticalRulerView = DroidCodeLineNumberRuler(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting()
        }
        textView.font = typography.nsFont(size: 12)
        textView.backgroundColor = GhosttyService.shared.backgroundColor
        textView.textColor = SyntaxTheme.defaultForeground
        textView.insertionPointColor = SyntaxTheme.defaultForeground
        textView.typingAttributes = [
            .font: typography.nsFont(size: 12),
            .foregroundColor: SyntaxTheme.defaultForeground,
        ]
        scrollView.verticalRulerView?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DroidCodeEditor
        weak var textView: NSTextView?
        private var isHighlighting = false

        init(parent: DroidCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting()
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            isHighlighting = true
            let selected = textView.selectedRanges
            let fullRange = NSRange(location: 0, length: storage.length)
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([
                .font: font,
                .foregroundColor: SyntaxTheme.defaultForeground,
            ], range: fullRange)
            for span in spans(in: textView.string) where NSMaxRange(span.range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: SyntaxTheme.color(for: span.scope), range: span.range)
            }
            storage.endEditing()
            textView.selectedRanges = selected
            isHighlighting = false
        }

        private func spans(in source: String) -> [TreeSitterHighlightSpan] {
            switch parent.language {
            case .shell:
                TreeSitterShellHighlighter.spans(in: source)
            }
        }
    }
}

private final class DroidCodeTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
}
