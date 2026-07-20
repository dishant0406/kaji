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
        platform: String = KajiCodePlatform.current,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        versionsDirectory(env: env)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent(platform, isDirectory: true)
    }

    static func bundledBinaryURL(fileManager: FileManager = .default) -> URL? {
        let candidates = [
            Bundle.appResources.url(forResource: "kajicode", withExtension: nil, subdirectory: "KajiCode"),
            Bundle.appResources.resourceURL?.appendingPathComponent("KajiCode/kajicode"),
        ].compactMap(\.self)
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
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
