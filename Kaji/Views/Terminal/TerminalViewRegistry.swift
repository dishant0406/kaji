import AppKit

@MainActor
final class TerminalViewRegistry {
    static let shared = TerminalViewRegistry()

    private var views: [UUID: GhosttyTerminalNSView] = [:]
    private var paneIDs: [ObjectIdentifier: UUID] = [:]

    private init() {}

    func view(for paneID: UUID, workingDirectory: String, command: String? = nil) -> GhosttyTerminalNSView {
        if let existing = views[paneID] {
            return existing
        }
        let view = GhosttyTerminalNSView(workingDirectory: workingDirectory, command: command)
        views[paneID] = view
        paneIDs[ObjectIdentifier(view)] = paneID
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

    func removeAll() {
        let retainedViews = views
        views.removeAll()
        paneIDs.removeAll()
        retainedViews.values.forEach { $0.tearDown() }
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

    func diagnosticsSnapshot() -> TerminalViewDiagnosticsSnapshot {
        TerminalViewDiagnosticsSnapshot(
            retainedViewCount: views.count,
            liveSurfaceCount: views.values.filter(\.hasLiveSurface).count,
            visibleSurfaceCount: views.values.filter(\.isTerminalSurfaceVisible).count
        )
    }

    func paneID(for view: GhosttyTerminalNSView) -> UUID? {
        paneIDs[ObjectIdentifier(view)]
    }
}

extension TerminalViewRegistry: TerminalViewRemoving {}

struct TerminalViewDiagnosticsSnapshot: Equatable {
    let retainedViewCount: Int
    let liveSurfaceCount: Int
    let visibleSurfaceCount: Int
}
