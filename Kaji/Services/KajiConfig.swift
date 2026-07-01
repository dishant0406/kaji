import Foundation

@MainActor @Observable
final class KajiConfig {
    static let shared = KajiConfig()

    let termyConfigURL: URL

    private static let termyConfigFilename = "termy.conf"

    private init() {
        let dir = KajiFileStorage.appSupportDirectory()
        termyConfigURL = dir.appendingPathComponent(Self.termyConfigFilename)
        seedConfigIfNeeded()
    }

    var termyConfigPath: String {
        termyConfigURL.path
    }

    func readTermyConfig() -> String {
        (try? String(contentsOf: termyConfigURL, encoding: .utf8)) ?? ""
    }

    func writeTermyConfig(_ content: String) throws {
        let data = Data(content.utf8)
        try data.write(to: termyConfigURL, options: .atomic)
        Self.restrictFilePermissions(termyConfigURL)
    }

    func updateConfigValue(_ key: String, value: String) {
        let entry = "\(key) = \(value)"
        var content = readTermyConfig()
        var lines = content.components(separatedBy: "\n")

        if let index = findConfigLineIndex(for: key, in: lines) {
            lines[index] = entry
        } else {
            lines.insert(entry, at: 0)
        }

        content = lines.joined(separator: "\n")
        try? writeTermyConfig(content)
    }

    func configValue(for key: String) -> String? {
        let lines = readTermyConfig().components(separatedBy: .newlines)
        guard let index = findConfigLineIndex(for: key, in: lines) else { return nil }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let afterKey = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return afterKey.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private func findConfigLineIndex(for key: String, in lines: [String]) -> Int? {
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let afterKey = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard afterKey.hasPrefix("=") else { continue }
            return i
        }
        return nil
    }

    private func seedConfigIfNeeded() {
        guard !FileManager.default.fileExists(atPath: termyConfigURL.path) else { return }
        try? writeTermyConfig("")
    }

    private static func restrictFilePermissions(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
