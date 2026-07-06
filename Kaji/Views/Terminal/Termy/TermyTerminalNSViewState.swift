import AppKit

extension TermyTerminalNSView {
    func startStatePolling() {
        guard titlePollTimer == nil else { return }
        stopStatePolling()
        titlePollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollState() }
        }
    }

    func stopStatePolling() {
        titlePollTimer?.invalidate()
        titlePollTimer = nil
    }

    func pollState() {
        guard let terminal else { return }
        if terminal.title != lastTitle {
            lastTitle = terminal.title
            onTitleChange?(terminal.title)
        }
        if terminal.isExited, !processExitHandled {
            processExitHandled = true
            if closesOnCommandExit { onProcessExit?() }
        }
        if searchVisible { publishSearchState() }
    }

    func focusKeyboardCapture() {
        guard let candidate = firstFocusableDescendant(in: self) else { return }
        window?.makeFirstResponder(candidate)
    }

    func ownsFirstResponder(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return view === self || view.isDescendant(of: self)
    }

    func firstFocusableDescendant(in view: NSView) -> NSView? {
        for subview in view.subviews {
            if subview.acceptsFirstResponder { return subview }
            if let found = firstFocusableDescendant(in: subview) { return found }
        }
        return nil
    }
}
