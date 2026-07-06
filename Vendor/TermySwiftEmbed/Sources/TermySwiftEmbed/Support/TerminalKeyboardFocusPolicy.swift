enum TerminalKeyboardFocusTrigger {
    case renderUpdate
    case windowAttachment
    case explicitHostRequest
    case pointerInput
    case dropInput
}

enum TerminalKeyboardFocusPolicy {
    static func allowsFirstResponderRequest(
        isInputEnabled: Bool,
        trigger: TerminalKeyboardFocusTrigger
    ) -> Bool {
        guard isInputEnabled else { return false }

        switch trigger {
        case .renderUpdate,
             .windowAttachment:
            return false
        case .explicitHostRequest,
             .pointerInput,
             .dropInput:
            return true
        }
    }
}
