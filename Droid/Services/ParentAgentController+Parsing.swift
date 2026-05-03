import Foundation

@MainActor
extension ParentAgentController {
    func splitDirection(from value: String?) -> SplitDirection {
        value?.lowercased() == "vertical" ? .vertical : .horizontal
    }

    func runIDs(from value: String?) -> [UUID] {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return value
            .split(separator: ",")
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func timeout(from value: String?) -> TimeInterval {
        guard let value, let parsed = TimeInterval(value) else { return 1_800 }
        return max(5, min(parsed, 600))
    }

    func sleepSeconds(from value: String?) -> TimeInterval {
        guard let value, let parsed = TimeInterval(value) else { return 5 }
        return max(3, min(parsed, 30))
    }

    func shouldFinishWaiting(runs: [AgentRun], taskID: UUID?) -> Bool {
        if runs.contains(where: { $0.status == .needsAttention || $0.status == .failed }) { return true }
        if !runs.isEmpty { return runs.allSatisfy(hasSettledClosedState) }
        guard let taskID,
              let task = store.tasks.first(where: { $0.id == taskID })
        else { return true }
        return task.childRunIDs.isEmpty
    }

    func hasSettledClosedState(_ run: AgentRun) -> Bool {
        guard isClosed(run) else { return false }
        if hasMeaningfulCompletion(run) { return true }
        return Date().timeIntervalSince(run.lastEventAt) > 8
    }

    func hasMeaningfulCompletion(_ run: AgentRun) -> Bool {
        if ChildAgentFeedStore.shared.finalAnswer(runID: run.id) != nil { return true }
        guard let event = run.events.last(where: { $0.kind == .completed || $0.kind == .transcript }) else { return false }
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        return !["started", "session completed", "turn completed"].contains(text)
    }

    func isClosed(_ run: AgentRun) -> Bool {
        run.status == .completed || run.status == .failed || run.status == .stale
    }

    func worktreeSlug(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let collapsed = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }

    func uuid(from value: String?) -> UUID? {
        guard let value else { return nil }
        return UUID(uuidString: value)
    }
}
