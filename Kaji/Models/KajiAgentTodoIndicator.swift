struct KajiAgentTodoIndicator: Equatable {
    let title: String
    let detail: String
    let icon: String

    static func active(phases: [KajiAgentTodoPhase]) -> KajiAgentTodoIndicator? {
        let tasks = phases.flatMap(\.tasks)
        guard !tasks.isEmpty else { return nil }
        let openTasks = tasks.filter { !$0.isClosed }
        guard !openTasks.isEmpty else { return nil }
        let inProgressCount = openTasks.count { $0.status == "in_progress" }
        let title = openTasks.count == 1 ? "1 todo open" : "\(openTasks.count) todos open"
        let detailParts = [
            "\(tasks.count) total",
            "\(inProgressCount) in progress",
            "\(tasks.count { $0.status == "completed" }) completed",
        ]
        return KajiAgentTodoIndicator(
            title: title,
            detail: detailParts.joined(separator: " · "),
            icon: inProgressCount > 0 ? "arrow.right.circle.fill" : "checklist"
        )
    }
}

private extension KajiAgentTodoItem {
    var isClosed: Bool {
        status == "completed" || status == "abandoned"
    }
}
