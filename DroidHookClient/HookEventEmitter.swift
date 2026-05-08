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

    static func emitSession(provider: String, input: String, source: String) {
        guard let paneID = ProcessInfo.processInfo.environment["DROID_PANE_ID"], !paneID.isEmpty else { return }
        guard let object = HookJSONExtractor.object(from: input) else { return }
        let sessionID = string(in: object, keys: ["session_id", "sessionID", "sessionId"])
        guard !sessionID.isEmpty else { return }
        var body: [String: String] = [
            "sessionID": sessionID,
            "source": source,
        ]
        insert("transcriptPath", value: string(in: object, keys: ["transcript_path", "transcriptPath"]), into: &body)
        insert("cwd", value: string(in: object, keys: ["cwd"]), into: &body)
        insert("title", value: string(in: object, keys: ["title", "name"]), into: &body)
        for key in ["DROID_PROJECT_ID", "DROID_WORKTREE_ID", "DROID_WORKTREE_PATH"] {
            guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { continue }
            let bodyKey = key == "DROID_PROJECT_ID" ? "projectID" : key == "DROID_WORKTREE_ID" ? "worktreeID" : "worktreePath"
            body[bodyKey] = value
        }
        emitSession(provider: provider, paneID: paneID, body: body)
    }

    static func emitSession(provider: String, paneID: String, sessionID: String, source: String, title: String? = nil) {
        let cleanedSessionID = HookTextSanitizer.clean(sessionID)
        guard !cleanedSessionID.isEmpty else { return }
        var body: [String: String] = [
            "sessionID": cleanedSessionID,
            "source": HookTextSanitizer.clean(source),
        ]
        insert("title", value: title.map { HookTextSanitizer.clean($0) }, into: &body)
        for key in ["DROID_PROJECT_ID", "DROID_WORKTREE_ID", "DROID_WORKTREE_PATH"] {
            guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { continue }
            let bodyKey = key == "DROID_PROJECT_ID" ? "projectID" : key == "DROID_WORKTREE_ID" ? "worktreeID" : "worktreePath"
            body[bodyKey] = value
        }
        emitSession(provider: provider, paneID: paneID, body: body)
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

    private static func emitSession(provider: String, paneID: String, body: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return }
        emit(type: "\(provider)_session", paneID: paneID, title: "session", body: text)
    }

    private static func string(in object: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = object[key] as? String {
                let cleaned = HookTextSanitizer.clean(value)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return ""
    }

    private static func insert(_ key: String, value: String?, into body: inout [String: String]) {
        guard let value, !value.isEmpty else { return }
        body[key] = value
    }
}
