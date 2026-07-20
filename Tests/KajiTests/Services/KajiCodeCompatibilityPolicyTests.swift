import Foundation
import Testing
@testable import Kaji

struct KajiCodeCompatibilityPolicyTests {
    @Test
    func selectsLatestCompatiblePlatformAsset() throws {
        let channel = KajiCodeChannel(
            schemaVersion: 1,
            generatedAt: "2026-07-20T00:00:00Z",
            latest: "0.4.3",
            entries: [
                entry(version: "0.4.1", protocolVersion: 1, minKajiVersion: "0.4.1"),
                entry(version: "0.4.3", protocolVersion: 2, minKajiVersion: "0.4.1"),
                entry(version: "0.4.2", protocolVersion: 1, minKajiVersion: "0.4.1"),
            ]
        )

        let selected = KajiCodeCompatibilityPolicy.latestCompatibleEntry(
            in: channel,
            currentKajiVersion: "0.4.1",
            platform: "macos-arm64"
        )

        #expect(selected?.version == "0.4.2")
        #expect(KajiCodeCompatibilityPolicy.asset(for: selected!, platform: "macos-arm64")?.size == 12)
    }

    @Test
    func rejectsUnsupportedSchemaAndKajiVersion() {
        let unsupportedSchema = KajiCodeChannel(
            schemaVersion: 2,
            generatedAt: "",
            latest: "0.4.2",
            entries: [entry(version: "0.4.2", protocolVersion: 1, minKajiVersion: "0.4.1")]
        )
        let futureOnly = KajiCodeChannel(
            schemaVersion: 1,
            generatedAt: "",
            latest: "0.5.0",
            entries: [entry(version: "0.5.0", protocolVersion: 1, minKajiVersion: "0.5.0")]
        )

        #expect(KajiCodeCompatibilityPolicy.latestCompatibleEntry(
            in: unsupportedSchema,
            currentKajiVersion: "0.4.1",
            platform: "macos-arm64"
        ) == nil)
        #expect(KajiCodeCompatibilityPolicy.latestCompatibleEntry(
            in: futureOnly,
            currentKajiVersion: "0.4.1",
            platform: "macos-arm64"
        ) == nil)
    }

    private func entry(version: String, protocolVersion: Int, minKajiVersion: String) -> KajiCodeChannelEntry {
        KajiCodeChannelEntry(
            version: version,
            protocolVersion: protocolVersion,
            minKajiVersion: minKajiVersion,
            maxKajiVersion: nil,
            assets: [
                "macos-arm64": KajiCodeChannelAsset(
                    url: URL(string: "https://example.com/kajicode-\(version).tar.gz")!,
                    sha256: String(repeating: "a", count: 64),
                    size: 12
                ),
            ]
        )
    }
}
