import Foundation

enum KajiCodeCompatibilityPolicy {
    static let supportedSchemaVersion = 1
    static let supportedProtocolVersion = 1

    static func latestCompatibleEntry(
        in channel: KajiCodeChannel,
        currentKajiVersion: String,
        platform: String = KajiCodePlatform.current
    ) -> KajiCodeChannelEntry? {
        guard channel.schemaVersion == supportedSchemaVersion else { return nil }
        let current = KajiCodeVersion(currentKajiVersion)
        return channel.entries
            .filter { entry in
                entry.protocolVersion == supportedProtocolVersion &&
                    KajiCodeVersion(entry.minKajiVersion) <= current &&
                    maxVersionAllows(entry.maxKajiVersion, current: current) &&
                    entry.assets[platform] != nil
            }
            .max { KajiCodeVersion($0.version) < KajiCodeVersion($1.version) }
    }

    static func asset(
        for entry: KajiCodeChannelEntry,
        platform: String = KajiCodePlatform.current
    ) -> KajiCodeChannelAsset? {
        entry.assets[platform]
    }

    private static func maxVersionAllows(_ value: String?, current: KajiCodeVersion) -> Bool {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return current <= KajiCodeVersion(value)
    }
}

enum KajiCodePlatform {
    static var current: String {
        #if os(macOS)
        #if arch(arm64)
        "macos-arm64"
        #else
        "macos-x64"
        #endif
        #else
        "unsupported"
        #endif
    }
}
