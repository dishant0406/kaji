import Foundation
import os

private let aiGatewayCredentialLogger = Logger(subsystem: "app.kaji", category: "AIGatewayCredentials")

protocol AIGatewayCredentialStoreProtocol {
    func load(account: String) -> String
    func save(_ value: String, account: String)
    func delete(account: String)
}

final class AIGatewayCredentialStore: AIGatewayCredentialStoreProtocol, @unchecked Sendable {
    static let shared = AIGatewayCredentialStore()

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL = KajiFileStorage.fileURL(filename: "ai-gateway-secrets.json")) {
        self.fileURL = fileURL
    }

    func load(account: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked()[account] ?? ""
    }

    func save(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        var values = readUnlocked()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            values.removeValue(forKey: account)
        } else {
            values[account] = trimmedValue
        }
        writeUnlocked(values)
    }

    func delete(account: String) {
        lock.lock()
        defer { lock.unlock() }
        var values = readUnlocked()
        values.removeValue(forKey: account)
        writeUnlocked(values)
    }

    private func readUnlocked() -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            aiGatewayCredentialLogger.error("Failed to read AI Gateway credentials: \(error.localizedDescription)")
            return [:]
        }
    }

    private func writeUnlocked(_ values: [String: String]) {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            guard !values.isEmpty else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(values)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            aiGatewayCredentialLogger.error("Failed to save AI Gateway credentials: \(error.localizedDescription)")
        }
    }
}

enum AIGatewayCredentialAccount {
    static let gatewayToken = "gateway-token"

    static func providerKey(_ providerID: String) -> String {
        "provider-\(providerID)-api-key"
    }
}
