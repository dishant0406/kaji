import Foundation

struct DroidBrowserControlCommand {
    let sessionID: String
    let action: String
    let arguments: [String: String]

    init?(body: String, defaultSessionID: String) {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = object["action"] as? String
        else { return nil }
        self.action = action
        sessionID = object["sessionId"] as? String ?? defaultSessionID
        arguments = (object["arguments"] as? [String: Any] ?? [:]).compactMapValues { value in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
    }
}
