import AppKit

@MainActor
final class TerminalViewRegistry {
    static let shared = TerminalViewRegistry()

    private var views: [UUID: GhosttyTerminalNSView] = [:]
    private var paneIDs: [ObjectIdentifier: UUID] = [:]

    private init() {}

    func view(for paneID: UUID, workingDirectory: String, command: String? = nil) -> GhosttyTerminalNSView {
        AskHangDebugLog.mark("TerminalViewRegistry.view.start", [
            "command": command == nil ? "nil" : "set",
            "existing": String(views[paneID] != nil),
            "paneID": paneID.uuidString,
        ])
        if let existing = views[paneID] {
            AskHangDebugLog.mark("TerminalViewRegistry.view.existing", ["paneID": paneID.uuidString])
            return existing
        }
        let view = GhosttyTerminalNSView(workingDirectory: workingDirectory, command: command)
        views[paneID] = view
        paneIDs[ObjectIdentifier(view)] = paneID
        AskHangDebugLog.mark("TerminalViewRegistry.view.created", ["paneID": paneID.uuidString])
        return view
    }

    func existingView(for paneID: UUID) -> GhosttyTerminalNSView? {
        views[paneID]
    }

    func removeView(for paneID: UUID) {
        guard let view = views.removeValue(forKey: paneID) else { return }
        paneIDs.removeValue(forKey: ObjectIdentifier(view))
        view.tearDown()
    }

    func needsConfirmQuit(for paneID: UUID) -> Bool {
        views[paneID]?.needsConfirmQuit() ?? false
    }

    func view(for paneID: UUID) -> GhosttyTerminalNSView? {
        views[paneID]
    }

    func foregroundProcessGroupID(for paneID: UUID) -> Int32? {
        views[paneID]?.foregroundProcessGroupID()
    }

    func ttyName(for paneID: UUID) -> String? {
        views[paneID]?.ttyName()
    }

    func visibleText(for paneID: UUID) -> String? {
        views[paneID]?.visibleText()
    }

    func paneID(for view: GhosttyTerminalNSView) -> UUID? {
        paneIDs[ObjectIdentifier(view)]
    }
}

extension TerminalViewRegistry: TerminalViewRemoving {}
