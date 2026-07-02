struct TerminalPollOutcome: Equatable {
    var receivedEvents: Bool
    var patchedCellCount: Int
    var changedFrame: Bool
    var publishedFrame: Bool
    var forcedFullRefresh: Bool

    static let empty = TerminalPollOutcome(
        receivedEvents: false,
        patchedCellCount: 0,
        changedFrame: false,
        publishedFrame: false,
        forcedFullRefresh: false
    )

    var hasInputEchoActivity: Bool {
        patchedCellCount > 0 || changedFrame || publishedFrame
    }
}
