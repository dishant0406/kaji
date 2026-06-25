import Foundation

enum KajiBrowserSessionEnvironmentStore {
    static func fileURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("browser", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    static func write(_ state: KajiBrowserBrokerState, fileManager: FileManager = .default) {
        let file = fileURL()
        let values: [String: Any] = [
            "brokerUrl": state.brokerURL,
            "token": state.token,
            "sessionId": state.sessionID,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        do {
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.deletingLastPathComponent().path)
        } catch {}
    }

    static func remove(homeDirectory: String = NSHomeDirectory(), fileManager: FileManager = .default) {
        let file = fileURL(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: file.path) else { return }
        try? fileManager.removeItem(at: file)
    }
}
