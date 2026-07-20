import Foundation

enum KajiCodePaths {
    static let devBinaryKey = "KAJICODE_DEV_BIN"
    static let channelURLKey = "KAJICODE_CHANNEL_URL"
    static var defaultChannelURL: URL {
        guard let url = URL(string: "https://github.com/dishant0406/KajiCode/releases/latest/download/kaji-channel.json") else {
            fatalError("Invalid KajiCode channel URL")
        }
        return url
    }

    static func channelURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let value = env[channelURLKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: value), !value.isEmpty
        {
            return url
        }
        return defaultChannelURL
    }

    static func root(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        appSupportDirectory(env: env).appendingPathComponent("kajicode", isDirectory: true)
    }

    static func versionsDirectory(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(env: env).appendingPathComponent("versions", isDirectory: true)
    }

    static func stagingDirectory(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(env: env).appendingPathComponent("staging", isDirectory: true)
    }

    static func downloadsDirectory(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(env: env).appendingPathComponent("downloads", isDirectory: true)
    }

    static func manifestURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(env: env).appendingPathComponent("install-manifest.json")
    }

    static func channelCacheURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(env: env).appendingPathComponent("channel-cache.json")
    }

    static func installDirectory(
        version: String,
        platform: String,
        sha256: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard isSafeComponent(version),
              isSafeComponent(platform),
              sha256.count == 64,
              sha256.allSatisfy(\.isHexDigit)
        else { return nil }
        return versionsDirectory(env: env)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent(platform, isDirectory: true)
            .appendingPathComponent(sha256.lowercased(), isDirectory: true)
    }

    static func binaryURL(
        for manifest: KajiCodeInstallManifest,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        installDirectory(
            version: manifest.activeVersion,
            platform: manifest.platform,
            sha256: manifest.sha256,
            env: env
        )?.appendingPathComponent("kajicode", isDirectory: false)
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }

    private static func appSupportDirectory(env: [String: String]) -> URL {
        if let override = env["KAJI_APP_SUPPORT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return KajiFileStorage.appSupportDirectory()
    }
}
