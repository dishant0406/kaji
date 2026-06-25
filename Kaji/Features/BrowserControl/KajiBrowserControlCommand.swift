import Foundation

struct KajiBrowserControlCommand {
    let sessionID: String
    let action: String
    let arguments: KajiBrowserControlArguments

    init?(body: String, defaultSessionID: String) {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = object["action"] as? String
        else { return nil }
        self.action = KajiBrowserControlActionAlias.resolve(action)
        sessionID = object["sessionId"] as? String ?? defaultSessionID
        arguments = KajiBrowserControlArguments(values: object["arguments"] as? [String: Any] ?? [:])
    }
}
