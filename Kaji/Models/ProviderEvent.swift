import Foundation

struct ProviderEvent: Equatable {
    static let distributedName = Notification.Name("app.kaji.provider-event")
    static let distributedObject = "app.kaji.\(ProcessInfo.processInfo.processIdentifier)"

    let type: String
    let paneIDString: String?
    let title: String
    let body: String

    init(type: String, paneIDString: String?, title: String, body: String) {
        self.type = type
        self.paneIDString = paneIDString
        self.title = title.isEmpty ? "Task completed!" : title
        self.body = body
    }

    init?(socketMessage data: Data) {
        guard let message = String(data: data, encoding: .utf8) else { return nil }
        let parts = message.split(
            separator: "|",
            maxSplits: 3,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count >= 3 else { return nil }
        self.init(
            type: parts[0],
            paneIDString: parts[1],
            title: parts[2],
            body: parts.count > 3 ? parts[3] : ""
        )
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let type = userInfo["type"] as? String,
              let title = userInfo["title"] as? String
        else {
            return nil
        }
        self.init(
            type: type,
            paneIDString: userInfo["paneID"] as? String,
            title: title,
            body: userInfo["body"] as? String ?? ""
        )
    }
}
