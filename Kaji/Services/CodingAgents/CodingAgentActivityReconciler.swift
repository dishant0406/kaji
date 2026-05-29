import Foundation

@MainActor
final class CodingAgentActivityReconciler {
    static let shared = CodingAgentActivityReconciler()

    private var tasks: [Task<Void, Never>] = []

    private init() {}

    func reconcileNow(reason: String = "Agent activity was interrupted.") {
        let active = AIActivityStore.shared.activitiesByPaneID
        guard !active.isEmpty else { return }

        AIActivityStore.shared.markActivitiesStale(where: { activity in
            guard TerminalViewRegistry.shared.existingView(for: activity.paneID) != nil else { return true }
            return !providerProcessIsPresent(for: activity)
        }, message: reason)
    }

    func schedulePostWakeReconciliation() {
        cancelScheduledReconciliation()
        schedule(after: .seconds(2), reason: "Agent activity was interrupted by system wake.")
        schedule(after: .seconds(30), reason: "Agent activity did not resume after system wake.")
        schedule(after: .seconds(90), reason: "Agent activity stayed idle after system wake.")
    }

    func cancelScheduledReconciliation() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func schedule(after duration: Duration, reason: String) {
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.reconcileNow(reason: reason)
        }
        tasks.append(task)
    }

    private func providerProcessIsPresent(for activity: AIActivityStore.Activity) -> Bool {
        guard let processGroupID = TerminalViewRegistry.shared.foregroundProcessGroupID(for: activity.paneID) else { return false }
        guard let definition = CodingAgentRegistry.shared.definition(id: activity.providerID) else { return false }
        let samples = ProcessResourceSampler.samplesForProcessGroup(id: processGroupID)
        let names = Set((definition.executableNames + definition.processMatchNames).map { $0.lowercased() })
        return samples.contains { sample in
            let commandName = sample.processName.lowercased()
            return names.contains(commandName) || definition.processCommandMarkers.contains { marker in
                commandName.contains(marker.lowercased())
            }
        }
    }
}
