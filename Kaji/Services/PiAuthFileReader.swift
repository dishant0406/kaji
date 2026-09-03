import Foundation

enum PiAuthFileReader {
    static func credential(for authKey: String) -> String? {
        guard let credential = credentialObject(for: authKey),
              credential["type"] as? String == "api_key",
              let key = credential["key"] as? String,
              !key.isEmpty
        else { return nil }

        if key.hasPrefix("!") {
            return nil
        }
        if let environmentValue = ProcessInfo.processInfo.environment[key], !environmentValue.isEmpty {
            return environmentValue
        }
        return key
    }

    static func hasOAuthCredential(for authKey: String) -> Bool {
        guard let credential = credentialObject(for: authKey) else { return false }
        return credential["type"] as? String == "oauth" && credential["refresh"] is String
    }

    private static func credentialObject(for authKey: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[authKey] as? [String: Any]
    }

    private static var authURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".pi/agent/auth.json")
    }
}
