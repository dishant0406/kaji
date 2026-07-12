import Foundation

@MainActor @Observable
final class FooterTerminalStateStore {
    private var states: [UUID: TerminalPaneState] = [:]
    private var visibleProjectIDs: Set<UUID> = []

    func state(for projectID: UUID) -> TerminalPaneState? {
        states[projectID]
    }

    func isVisible(for projectID: UUID) -> Bool {
        visibleProjectIDs.contains(projectID)
    }

    var projectIDs: Set<UUID> {
        Set(states.keys).union(visibleProjectIDs)
    }

    @discardableResult
    func show(projectID: UUID, projectPath: String) -> TerminalPaneState {
        let state = states[projectID] ?? TerminalPaneState(projectPath: projectPath, title: "Footer Terminal")
        states[projectID] = state
        visibleProjectIDs.insert(projectID)
        return state
    }

    func collapse(projectID: UUID) {
        visibleProjectIDs.remove(projectID)
    }

    func collapseAll() {
        visibleProjectIDs.removeAll()
    }

    func remove(projectID: UUID) -> TerminalPaneState? {
        visibleProjectIDs.remove(projectID)
        return states.removeValue(forKey: projectID)
    }
}
