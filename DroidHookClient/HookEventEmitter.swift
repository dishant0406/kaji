import Foundation

enum HookEventEmitter {
    private static let eventName = Notification.Name("app.droid.provider-event")

    static func emit(type: String, paneID: String?, title: String, body: String) {
        guard !type.isEmpty else { return }
        guard let instanceID = ProcessInfo.processInfo.environment["DROID_INSTANCE_ID"], !instanceID.isEmpty else { return }
        let userInfo: [String: String] = [
            "type": type,
            "paneID": paneID ?? ProcessInfo.processInfo.environment["DROID_PANE_ID"] ?? "",
            "title": title,
            "body": body,
        ]
        DistributedNotificationCenter.default().postNotificationName(
            eventName,
            object: instanceID,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    static func emitActivity(provider: String, state: String) {
        guard let paneID = ProcessInfo.processInfo.environment["DROID_PANE_ID"], !paneID.isEmpty else { return }
        emit(
            type: "\(provider)_activity",
            paneID: paneID,
            title: state,
            body: context()
        )
    }

    static func emitTranscript(provider: String, kind: String, text: String) {
        guard let paneID = ProcessInfo.processInfo.environment["DROID_PANE_ID"], !paneID.isEmpty else { return }
        let cleaned = HookTextSanitizer.clean(text)
        guard !cleaned.isEmpty else { return }
        emit(
            type: "\(provider)_transcript",
            paneID: paneID,
            title: kind,
            body: cleaned
        )
    }

    private static func context() -> String {
        let env = ProcessInfo.processInfo.environment
        guard let projectID = env["DROID_PROJECT_ID"], !projectID.isEmpty,
              let worktreeID = env["DROID_WORKTREE_ID"], !worktreeID.isEmpty
        else {
            return ""
        }
        return [projectID, worktreeID, env["DROID_WORKTREE_PATH"] ?? ""].joined(separator: ",")
    }
}
