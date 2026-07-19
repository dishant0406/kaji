import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting notes settings store")
struct MeetingNotesSettingsStoreTests {
    @Test("defaults are local-first and remote synthesis remains unconfigured")
    func defaults() throws {
        let store = try makeStore()

        #expect(store.settings.synthesisIntervalMinutes == 2)
        #expect(store.settings.includeSystemAudio)
        #expect(store.settings.includeMicrophone)
        #expect(!store.settings.persistenceSettings.retainRawAudio)
        #expect(!store.settings.shareProjectContext)
        #expect(store.settings.contextScope == .active)
        #expect(!store.isModelConfigured)
        #expect(store.unavailableReason != nil)
        #expect(store.allowingDestructiveRetention)
    }

    @Test("updates clamp bounds and persist an explicit model selection")
    func normalizationAndPersistence() throws {
        let url = try settingsURL()
        let store = MeetingNotesSettingsStore(fileStore: .init(fileURL: url, options: .prettySorted))
        store.update {
            $0.synthesisIntervalMinutes = 100
            $0.retentionDays = 0
            $0.styleInstructions = String(repeating: "a", count: 3000)
        }
        store.configureModel(providerID: " provider ", modelID: " model ")
        let reloaded = MeetingNotesSettingsStore(fileStore: .init(fileURL: url, options: .prettySorted))

        #expect(reloaded.settings.synthesisIntervalMinutes == 30)
        #expect(reloaded.settings.retentionDays == 1)
        #expect(reloaded.settings.styleInstructions.count == 2000)
        #expect(reloaded.settings.modelSelector == "provider/model")
        #expect(reloaded.isModelConfigured)
        #expect(!reloaded.settings.persistenceSettings.retainRawAudio)
        #expect(reloaded.allowingDestructiveRetention)
    }

    @Test("malformed settings without a backup block destructive retention")
    func malformedSettingsBlockRetention() throws {
        let url = try settingsURL()
        try Data("{".utf8).write(to: url)

        let store = MeetingNotesSettingsStore(fileStore: .init(fileURL: url, options: .prettySorted))

        #expect(store.settings == .defaults)
        #expect(store.persistenceError != nil)
        #expect(!store.allowingDestructiveRetention)
    }

    @Test("a valid backup recovers malformed primary settings")
    func backupRecovery() throws {
        let url = try settingsURL()
        let original = MeetingNotesSettingsStore(fileStore: .init(fileURL: url, options: .prettySorted))
        original.update { $0.retentionDays = 93 }
        try Data("not-json".utf8).write(to: url, options: .atomic)

        let recovered = MeetingNotesSettingsStore(fileStore: .init(fileURL: url, options: .prettySorted))

        #expect(recovered.settings.retentionDays == 93)
        #expect(recovered.persistenceError != nil)
        #expect(recovered.allowingDestructiveRetention)
        let decoded = try JSONDecoder().decode(MeetingNotesIntegrationSettings.self, from: Data(contentsOf: url))
        #expect(decoded.retentionDays == 93)
    }

    @Test("settings and backup use private permissions and repair their directory")
    func securePermissions() throws {
        let url = try settingsURL()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
        let store = MeetingNotesSettingsStore(fileStore: .init(fileURL: url, options: .prettySorted))

        store.update { $0.retentionDays = 45 }

        #expect(try permissions(at: directory) == 0o700)
        #expect(try permissions(at: url) == 0o600)
        #expect(try permissions(at: url.appendingPathExtension("backup")) == 0o600)
    }

    @Test("settings reject a symbolic link parent without changing its target permissions")
    func symbolicLinkParentIsRejected() throws {
        let container = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let target = container.appendingPathComponent("Target", isDirectory: true)
        let link = container.appendingPathComponent("LinkedSettings", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let store = MeetingNotesSettingsStore(
            fileStore: .init(fileURL: link.appendingPathComponent("settings.json"), options: .prettySorted)
        )

        #expect(store.persistenceError != nil)
        #expect(!store.allowingDestructiveRetention)
        #expect(try permissions(at: target) == 0o755)
    }

    private func makeStore() throws -> MeetingNotesSettingsStore {
        MeetingNotesSettingsStore(fileStore: .init(fileURL: try settingsURL(), options: .prettySorted))
    }

    private func settingsURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("settings.json")
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }
}
