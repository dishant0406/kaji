import AppKit
import SwiftUI

struct TerminalKeyboardInputView: NSViewRepresentable {
    var cols: Int
    var rows: Int
    var renderConfig: TerminalRenderConfig
    var isInputEnabled: Bool
    var isSearchVisible: Bool
    var canCopy: Bool
    var onFocus: () -> Void
    var onBytes: ([UInt8]) -> Void
    var onKeyInput: (TerminalKeyInput) -> Void
    var onMouseInput: (TerminalMouseInput) -> Bool
    var onScrollLines: (Int) -> Void
    var onScrollToTop: () -> Void
    var onScrollToBottom: () -> Void
    var onClearBuffer: () -> Void
    var onSplitRight: () -> Void
    var onSplitDown: () -> Void
    var onClosePane: () -> Void
    var onClosePaneIfSplit: () -> Bool
    var onFocusNextPane: () -> Void
    var onHostCommand: (NSEvent) -> Bool = { _ in false }
    var onShowSearch: () -> Void
    var onDismissSearch: () -> Void
    var onSelectionChanged: (TerminalSelection?) -> Void
    var onSelectWord: (TerminalGridPosition) -> Void
    var onSelectLine: (TerminalGridPosition) -> Void
    var onSelectAll: () -> Void
    var onHoverProbe: (TerminalGridPosition?) -> Bool
    var onOpenLink: (TerminalGridPosition) -> Bool
    var onCopy: () -> Bool
    var onPaste: (String) -> Void
    var onMarkedTextChanged: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> KeyboardCaptureView {
        let view = KeyboardCaptureView()
        view.apply(configuration: self)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.registerForDraggedTypes(TerminalDropInput.acceptedPasteboardTypes)
        return view
    }

    func updateNSView(_ view: KeyboardCaptureView, context: Context) {
        view.apply(configuration: self)
        view.focus(trigger: .renderUpdate)
    }
}

final class KeyboardCaptureView: NSView {
    var cols = 0
    var rows = 0
    var renderConfig = TerminalRenderConfig.default
    var isInputEnabled = true
    var isSearchVisible = false
    var canCopy = false
    var onFocus: () -> Void = {}
    var onBytes: ([UInt8]) -> Void = { _ in }
    var onKeyInput: (TerminalKeyInput) -> Void = { _ in }
    var onMouseInput: (TerminalMouseInput) -> Bool = { _ in false }
    var onScrollLines: (Int) -> Void = { _ in }
    var onScrollToTop: () -> Void = {}
    var onScrollToBottom: () -> Void = {}
    var onClearBuffer: () -> Void = {}
    var onSplitRight: () -> Void = {}
    var onSplitDown: () -> Void = {}
    var onClosePane: () -> Void = {}
    var onClosePaneIfSplit: () -> Bool = { false }
    var onFocusNextPane: () -> Void = {}
    var onHostCommand: (NSEvent) -> Bool = { _ in false }
    var onShowSearch: () -> Void = {}
    var onDismissSearch: () -> Void = {}
    var onSelectionChanged: (TerminalSelection?) -> Void = { _ in }
    var onSelectWord: (TerminalGridPosition) -> Void = { _ in }
    var onSelectLine: (TerminalGridPosition) -> Void = { _ in }
    var onSelectAll: () -> Void = {}
    var onHoverProbe: (TerminalGridPosition?) -> Bool = { _ in false }
    var onOpenLink: (TerminalGridPosition) -> Bool = { _ in false }
    var onCopy: () -> Bool = { false }
    var onPaste: (String) -> Void = { _ in }
    var onMarkedTextChanged: (String) -> Void = { _ in }

    private var selectionAnchor: TerminalGridPosition?
    private var didDragSelection = false
    private var preciseScrollRemainder: CGFloat = 0
    private var preciseHorizontalScrollRemainder: CGFloat = 0
    private var activeMouseButton: TerminalMouseButton?

    // IME composition state. `markedText` holds the in-progress composition;
    // the two flags let `insertText` tell an IME commit apart from a plain key.
    private var markedText = ""
    private var composingBeforeEvent = false
    private var imeCommitted = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isInputEnabled,
              let bytes = TerminalDropInput.bytes(from: sender.draggingPasteboard)
        else {
            return false
        }

        onFocus()
        focus(trigger: .dropInput)
        onBytes(bytes)
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInputEnabled || isSearchVisible else {
            return nil
        }
        guard bounds.contains(point) else { return nil }

        if let window, let superview {
            let windowPoint = superview.convert(point, to: nil)
            if !window.contentLayoutRect.contains(windowPoint) {
                return nil
            }
        }

        return self
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focus(trigger: .windowAttachment)
    }

    override func mouseDown(with event: NSEvent) {
        handleMouseDown(event, button: .left)
    }

    override func rightMouseDown(with event: NSEvent) {
        handleRightMouseDown(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        handleMouseDown(event, button: .middle)
    }

    private func handleMouseDown(_ event: NSEvent, button: TerminalMouseButton) {
        guard isInputEnabled else {
            if isSearchVisible {
                onFocus()
                onDismissSearch()
                focus(trigger: .pointerInput)
                return
            }
            super.mouseDown(with: event)
            return
        }
        onFocus()
        focus(trigger: .pointerInput)
        didDragSelection = false

        if button == .left,
           event.modifierFlags.contains(.control)
        {
            activeMouseButton = nil
            selectionAnchor = nil
            showTerminalContextMenu(for: event)
            return
        }

        // ⌘-click opens a URL under the pointer.
        if button == .left,
           event.modifierFlags.contains(.command),
           onOpenLink(gridPosition(for: event))
        {
            return
        }

        if sendMouse(kind: .press, button: button, event: event) {
            activeMouseButton = button
            selectionAnchor = nil
            onSelectionChanged(nil)
            return
        }

        activeMouseButton = nil
        guard button == .left else {
            return
        }

        // Double-click selects the word, triple-click selects the line.
        switch event.clickCount {
        case 2:
            selectionAnchor = nil
            onSelectWord(gridPosition(for: event))
            return
        case let count where count >= 3:
            selectionAnchor = nil
            onSelectLine(gridPosition(for: event))
            return
        default:
            break
        }

        selectionAnchor = gridPosition(for: event)
        onSelectionChanged(nil)
    }

    private func handleRightMouseDown(_ event: NSEvent) {
        guard isInputEnabled else {
            super.rightMouseDown(with: event)
            return
        }
        onFocus()
        focus(trigger: .pointerInput)
        didDragSelection = false

        if event.modifierFlags.contains(.control) {
            activeMouseButton = nil
            selectionAnchor = nil
            showTerminalContextMenu(for: event)
            return
        }

        if sendMouse(kind: .press, button: .right, event: event) {
            activeMouseButton = .right
            selectionAnchor = nil
            onSelectionChanged(nil)
            return
        }

        activeMouseButton = nil
        selectionAnchor = nil
        showTerminalContextMenu(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouseDragged(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handleMouseDragged(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        handleMouseDragged(event)
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard isInputEnabled else {
            super.mouseDragged(with: event)
            return
        }
        if let activeMouseButton,
           sendMouse(kind: .drag, button: activeMouseButton, event: event)
        {
            return
        }
        guard let anchor = selectionAnchor else {
            return
        }
        guard let selection = Self.dragSelection(anchor: anchor, active: gridPosition(for: event)) else {
            return
        }
        didDragSelection = true
        onSelectionChanged(selection)
    }

    override func mouseUp(with event: NSEvent) {
        handleMouseUp(event, button: .left)
    }

    override func rightMouseUp(with event: NSEvent) {
        handleMouseUp(event, button: .right)
    }

    override func otherMouseUp(with event: NSEvent) {
        handleMouseUp(event, button: .middle)
    }

    private func handleMouseUp(_ event: NSEvent, button: TerminalMouseButton) {
        guard isInputEnabled else {
            super.mouseUp(with: event)
            return
        }
        if activeMouseButton != nil {
            _ = sendMouse(kind: .release, button: button, event: event)
            activeMouseButton = nil
            return
        }
        guard let anchor = selectionAnchor else {
            return
        }

        defer {
            selectionAnchor = nil
            didDragSelection = false
        }

        guard didDragSelection else {
            onSelectionChanged(nil)
            return
        }

        onSelectionChanged(Self.dragSelection(anchor: anchor, active: gridPosition(for: event)))
    }

    override func mouseMoved(with event: NSEvent) {
        guard isInputEnabled else {
            super.mouseMoved(with: event)
            return
        }
        let consumed = sendMouse(kind: .move, button: .none, event: event)
        let position = consumed ? nil : gridPosition(for: event)
        if onHoverProbe(position) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isInputEnabled else {
            super.keyDown(with: event)
            return
        }
        onFocus()

        if isSearchVisible, event.keyCode == MacKeyCode.escape.rawValue {
            onDismissSearch()
            return
        }

        if handleHostCommand(event) || handleCopy(event) || handlePaste(event) {
            return
        }

        // Let the input context compose IME/dead-key input. Routed only while
        // composing, or for plain/shift keys — `option` stays meta and `command`
        // stays a shortcut. Non-IME keys produce no marked text and fall through
        // to the terminal encoder below unchanged.
        if shouldRouteThroughInputContext(event) {
            if processIMEKeyDown(event) {
                return
            }
        }

        if event.modifierFlags.contains(.command) {
            // cmd+up/down scroll the viewport to the history extremes.
            if handleCommandScroll(event) {
                return
            }
            // Forward macOS line-editing shortcuts (cmd+arrows/backspace/delete);
            // the core maps these to ^A/^E/^U/^K. Everything else falls through
            // to the menu/responder chain.
            if let keyCode = MacKeyCode(rawValue: event.keyCode),
               isLineEditingKeyCode(keyCode),
               let keyInput = terminalKeyInput(for: event)
            {
                onKeyInput(keyInput)
                return
            }
            super.keyDown(with: event)
            return
        }

        if let keyInput = terminalKeyInput(for: event) {
            onKeyInput(keyInput)
            return
        }

        super.keyDown(with: event)
    }

    /// Feeds an event to the input context. Returns true when the IME consumed
    /// it (composing, committed, or canceled a composition); false means it was
    /// a plain key the terminal encoder should handle.
    private func processIMEKeyDown(_ event: NSEvent) -> Bool {
        composingBeforeEvent = hasMarkedText()
        imeCommitted = false
        inputContext?.handleEvent(event)
        if hasMarkedText() || imeCommitted {
            return true
        }
        // True only if a composition just ended (e.g. Escape canceled it), so
        // the cancel key isn't also sent to the terminal.
        return composingBeforeEvent
    }

    private func shouldRouteThroughInputContext(_ event: NSEvent) -> Bool {
        Self.shouldRouteThroughInputContext(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            hasMarkedText: hasMarkedText()
        )
    }

    nonisolated static func shouldRouteThroughInputContext(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> Bool {
        if hasMarkedText {
            return true
        }

        if modifierFlags.contains(.command) || modifierFlags.contains(.option) {
            return false
        }

        if let special = specialKey(for: keyCode) {
            return special.usesCharacter
        }

        return true
    }

    /// Special keys are encoded by the terminal path, not AppKit's text-editing
    /// command selectors; swallowing them keeps the input context from beeping.
    override func doCommand(by selector: Selector) {}

    private func isLineEditingKeyCode(_ keyCode: MacKeyCode) -> Bool {
        switch keyCode {
        case .deleteBackward,
             .forwardDelete,
             .leftArrow,
             .rightArrow,
             .home,
             .end:
            true
        default:
            false
        }
    }

    private func handleCommandScroll(_ event: NSEvent) -> Bool {
        guard let keyCode = MacKeyCode(rawValue: event.keyCode) else {
            return false
        }

        switch keyCode {
        case .upArrow:
            onScrollToTop()
            return true
        case .downArrow:
            onScrollToBottom()
            return true
        default:
            return false
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isInputEnabled else {
            super.scrollWheel(with: event)
            return
        }
        onFocus()

        let deltaLines = scrollLines(
            delta: scaledScrollDelta(event.scrollingDeltaY),
            unit: renderConfig.cellHeight,
            precise: event.hasPreciseScrollingDeltas,
            remainder: &preciseScrollRemainder
        )
        let horizontalDeltaLines = scrollLines(
            delta: scaledScrollDelta(event.scrollingDeltaX),
            unit: renderConfig.cellWidth,
            precise: event.hasPreciseScrollingDeltas,
            remainder: &preciseHorizontalScrollRemainder
        )

        if sendWheelEvents(vertical: deltaLines, horizontal: horizontalDeltaLines, event: event) {
            return
        }

        if deltaLines != 0 {
            onScrollLines(deltaLines)
        }
    }

    func focus(trigger: TerminalKeyboardFocusTrigger = .explicitHostRequest) {
        guard TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
            isInputEnabled: isInputEnabled,
            trigger: trigger
        )
        else {
            return
        }
        guard let window, window.firstResponder !== self else {
            return
        }
        window.makeFirstResponder(self)
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard isInputEnabled,
              TerminalDropInput.canDecode(sender.draggingPasteboard)
        else {
            return []
        }
        return .copy
    }

    private func scrollLines(
        delta: CGFloat,
        unit: CGFloat,
        precise: Bool,
        remainder: inout CGFloat
    ) -> Int {
        if precise {
            let rawLines = (delta / max(1, unit)) + remainder
            let wholeLines = rawLines.rounded(.towardZero)
            remainder = rawLines - wholeLines
            return Int(wholeLines)
        }
        return Int(delta.rounded())
    }

    private func scaledScrollDelta(_ delta: CGFloat) -> CGFloat {
        delta * max(0.0, renderConfig.mouseScrollMultiplier)
    }

    private func sendWheelEvents(vertical: Int, horizontal: Int, event: NSEvent) -> Bool {
        var didSend = false
        if vertical != 0 {
            let kind: TerminalMouseEventKind = vertical > 0 ? .wheelUp : .wheelDown
            didSend = sendRepeatedMouse(kind: kind, count: abs(vertical), event: event) || didSend
        }
        if horizontal != 0 {
            let kind: TerminalMouseEventKind = horizontal > 0 ? .wheelLeft : .wheelRight
            didSend = sendRepeatedMouse(kind: kind, count: abs(horizontal), event: event) || didSend
        }
        return didSend
    }

    private func sendRepeatedMouse(
        kind: TerminalMouseEventKind,
        count: Int,
        event: NSEvent
    ) -> Bool {
        let count = min(count, 32)
        guard count > 0, sendMouse(kind: kind, button: .none, event: event) else {
            return false
        }
        guard count > 1 else {
            return true
        }
        for _ in 1 ..< count {
            _ = sendMouse(kind: kind, button: .none, event: event)
        }
        return true
    }

    private func sendMouse(
        kind: TerminalMouseEventKind,
        button: TerminalMouseButton,
        event: NSEvent
    ) -> Bool {
        let flags = event.modifierFlags
        return onMouseInput(TerminalMouseInput(
            kind: kind,
            button: button,
            position: gridPosition(for: event),
            control: flags.contains(.control),
            alt: flags.contains(.option),
            shift: flags.contains(.shift)
        ))
    }

    private func handleCopy(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return false
        }
        return onCopy()
    }

    private func handlePaste(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "v",
              let text = NSPasteboard.general.string(forType: .string)
        else {
            return false
        }

        onPaste(text)
        return true
    }

    private func pasteFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        onPaste(text)
    }

    private func showTerminalContextMenu(for event: NSEvent) {
        let menu = TerminalSurfaceContextMenu.make(
            canCopy: canCopy,
            canPaste: NSPasteboard.general.string(forType: .string) != nil,
            target: self
        )
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc
    func copyFromTerminalContextMenu(_ sender: Any?) {
        _ = onCopy()
    }

    @objc
    func pasteFromTerminalContextMenu(_ sender: Any?) {
        pasteFromPasteboard()
    }

    @objc
    func selectAllFromTerminalContextMenu(_ sender: Any?) {
        onSelectAll()
    }

    @objc
    func splitRightFromTerminalContextMenu(_ sender: Any?) {
        onSplitRight()
    }

    @objc
    func splitDownFromTerminalContextMenu(_ sender: Any?) {
        onSplitDown()
    }

    @objc
    func clearBufferFromTerminalContextMenu(_ sender: Any?) {
        onClearBuffer()
    }

    @objc
    func showSearchFromTerminalContextMenu(_ sender: Any?) {
        onShowSearch()
    }

    private func handleHostCommand(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        if onHostCommand(event) {
            return true
        }

        guard event.modifierFlags.contains(.command) else {
            return false
        }

        switch (key, event.modifierFlags.contains(.shift)) {
        case ("k", false):
            onClearBuffer()
            return true
        default:
            return false
        }
    }

    private func terminalKeyInput(for event: NSEvent) -> TerminalKeyInput? {
        guard let special = Self.specialKey(for: event.keyCode) else {
            return characterKeyInput(for: event)
        }
        return keyInput(
            special.key,
            event: event,
            keyChar: special.usesCharacter ? event.characters : nil,
            function: special.function
        )
    }

    /// Maps a macOS keyCode to the terminal key name, the function-key flag, and
    /// whether the typed character should ride along. Returns nil for keys that
    /// are encoded by their character instead.
    nonisolated static func specialKey(
        for keyCode: UInt16
    ) -> (key: String, function: Bool, usesCharacter: Bool)? {
        guard let keyCode = MacKeyCode(rawValue: keyCode) else {
            return nil
        }
        switch keyCode {
        case .returnKey,
             .keypadEnter: return ("enter", false, false)
        case .tab: return ("tab", false, false)
        case .deleteBackward: return ("backspace", false, false)
        case .escape: return ("escape", false, false)
        case .home: return ("home", false, false)
        case .end: return ("end", false, false)
        case .pageUp: return ("pageup", false, false)
        case .pageDown: return ("pagedown", false, false)
        case .forwardDelete: return ("delete", false, false)
        case .leftArrow: return ("left", false, false)
        case .rightArrow: return ("right", false, false)
        case .downArrow: return ("down", false, false)
        case .upArrow: return ("up", false, false)
        case .f1: return ("f1", true, false)
        case .f2: return ("f2", true, false)
        case .f3: return ("f3", true, false)
        case .f4: return ("f4", true, false)
        case .f5: return ("f5", true, false)
        case .f6: return ("f6", true, false)
        case .f7: return ("f7", true, false)
        case .f8: return ("f8", true, false)
        case .f9: return ("f9", true, false)
        case .f10: return ("f10", true, false)
        case .f11: return ("f11", true, false)
        case .f12: return ("f12", true, false)
        case .space: return ("space", false, true)
        }
    }

    private func characterKeyInput(for event: NSEvent) -> TerminalKeyInput? {
        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else {
            return nil
        }
        return keyInput(
            key.lowercased(),
            event: event,
            keyChar: event.characters
        )
    }

    private func keyInput(
        _ key: String,
        event: NSEvent,
        keyChar: String? = nil,
        function: Bool = false
    ) -> TerminalKeyInput {
        let flags = event.modifierFlags
        return TerminalKeyInput(
            key: key,
            keyChar: keyChar,
            control: flags.contains(.control),
            alt: flags.contains(.option),
            shift: flags.contains(.shift),
            platform: flags.contains(.command),
            function: flags.contains(.function) || function,
            eventKind: event.isARepeat ? .repeat : .press
        )
    }

    private func gridPosition(for event: NSEvent) -> TerminalGridPosition {
        let point = convert(event.locationInWindow, from: nil)
        let maxCol = max(0, cols - 1)
        let maxRow = max(0, rows - 1)
        let col = max(0, min(Int((point.x - renderConfig.paddingX) / renderConfig.cellWidth), maxCol))
        let topY = bounds.height - point.y - renderConfig.paddingY
        let rowFromTop = Int(topY / renderConfig.cellHeight)
        let row = max(0, min(rowFromTop, maxRow))
        return TerminalGridPosition(col: col, row: row)
    }

    nonisolated static func dragSelection(
        anchor: TerminalGridPosition,
        active: TerminalGridPosition
    ) -> TerminalSelection? {
        guard anchor != active else {
            return nil
        }
        return TerminalSelection(anchor: anchor, active: active)
    }
}

enum MacKeyCode: UInt16 {
    case returnKey = 36
    case keypadEnter = 76
    case tab = 48
    case deleteBackward = 51
    case escape = 53
    case home = 115
    case end = 119
    case pageUp = 116
    case pageDown = 121
    case forwardDelete = 117
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126
    case f1 = 122
    case f2 = 120
    case f3 = 99
    case f4 = 118
    case f5 = 96
    case f6 = 97
    case f7 = 98
    case f8 = 100
    case f9 = 101
    case f10 = 109
    case f11 = 103
    case f12 = 111
    case space = 49
}

/// AppKit calls NSTextInputClient on the main thread, so the conformance is
/// isolated to the main actor (matching this @MainActor NSView subclass).
extension KeyboardCaptureView: @MainActor NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        markedText = ""
        onMarkedTextChanged("")
        // A plain keystroke (no active composition) is left to the terminal
        // encoder in keyDown; only emit text that came from an IME commit.
        guard composingBeforeEvent || hasMarkedText() else {
            return
        }
        let text = Self.plainString(from: string)
        if !text.isEmpty {
            onBytes(Array(text.utf8))
        }
        imeCommitted = true
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = Self.plainString(from: string)
        onMarkedTextChanged(markedText)
    }

    func unmarkText() {
        markedText = ""
        onMarkedTextChanged("")
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Anchor IME candidate windows to the input view; cursor-cell
        // coordinates are not exposed through this NSView bridge.
        guard let window else {
            return .zero
        }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }

    private static func plainString(from value: Any) -> String {
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return value as? String ?? ""
    }
}

private extension KeyboardCaptureView {
    func apply(configuration: TerminalKeyboardInputView) {
        cols = configuration.cols
        rows = configuration.rows
        renderConfig = configuration.renderConfig
        isInputEnabled = configuration.isInputEnabled
        isSearchVisible = configuration.isSearchVisible
        canCopy = configuration.canCopy
        onFocus = configuration.onFocus
        onBytes = configuration.onBytes
        onKeyInput = configuration.onKeyInput
        onMouseInput = configuration.onMouseInput
        onScrollLines = configuration.onScrollLines
        onScrollToTop = configuration.onScrollToTop
        onScrollToBottom = configuration.onScrollToBottom
        onClearBuffer = configuration.onClearBuffer
        onSplitRight = configuration.onSplitRight
        onSplitDown = configuration.onSplitDown
        onClosePane = configuration.onClosePane
        onClosePaneIfSplit = configuration.onClosePaneIfSplit
        onFocusNextPane = configuration.onFocusNextPane
        onHostCommand = configuration.onHostCommand
        onShowSearch = configuration.onShowSearch
        onDismissSearch = configuration.onDismissSearch
        onSelectionChanged = configuration.onSelectionChanged
        onSelectWord = configuration.onSelectWord
        onSelectLine = configuration.onSelectLine
        onSelectAll = configuration.onSelectAll
        onHoverProbe = configuration.onHoverProbe
        onOpenLink = configuration.onOpenLink
        onCopy = configuration.onCopy
        onPaste = configuration.onPaste
        onMarkedTextChanged = configuration.onMarkedTextChanged
    }
}
