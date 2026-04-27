import Foundation

struct NotificationOutboundEvent: Equatable {
    let source: NotificationRouteSource
    let kind: NotificationEventKind
    let title: String
    let body: String
    let project: String
    let worktree: String
    let timestamp: Date

    var templateValues: [String: String] {
        [
            "title": title,
            "body": body,
            "source": source.rawValue,
            "event_kind": kind.rawValue,
            "project": project,
            "worktree": worktree,
            "timestamp_iso": ISO8601DateFormatter().string(from: timestamp),
        ]
    }

    static let sample = Self(
        source: .codex,
        kind: .completed,
        title: "Turn completed",
        body: "The run completed successfully.",
        project: "Droid",
        worktree: "muxy",
        timestamp: Date(timeIntervalSince1970: 0)
    )
}
