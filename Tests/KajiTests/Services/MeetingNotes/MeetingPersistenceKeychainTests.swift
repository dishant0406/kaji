import Foundation
import Security
import Testing

@testable import Kaji

@Suite("Meeting persistence Keychain compatibility")
struct MeetingPersistenceKeychainTests {
    @Test("unsigned builds use a private file without touching login Keychain")
    func missingEntitlementFallback() throws {
        let keychain = ScriptedMeetingKeychain(
            loads: [.init(status: errSecMissingEntitlement, data: nil)],
            adds: []
        )
        let fallback = InMemoryMeetingPersistenceKeyStore()
        let store = KeychainMeetingPersistenceKeyStore(
            keychain: keychain,
            developmentFallback: fallback
        )

        let material = try store.loadOrCreateKey()

        #expect(material.id.count == 16)
        #expect(material.key.count == 32)
        #expect(keychain.loadUsesDataProtection == [true])
        #expect(keychain.addUsesDataProtection.isEmpty)
        #expect(try store.loadOrCreateKey() == material)
    }

    @Test("missing entitlement while saving falls back without login Keychain access")
    func saveMissingEntitlementFallback() throws {
        let keychain = ScriptedMeetingKeychain(
            loads: [.init(status: errSecItemNotFound, data: nil)],
            adds: [errSecMissingEntitlement]
        )
        let fallback = InMemoryMeetingPersistenceKeyStore()
        let store = KeychainMeetingPersistenceKeyStore(
            keychain: keychain,
            developmentFallback: fallback
        )

        let material = try store.loadOrCreateKey()

        #expect(material.id.count == 16)
        #expect(keychain.loadUsesDataProtection == [true])
        #expect(keychain.addUsesDataProtection == [true])
    }

    @Test("locked or unavailable Keychain errors do not downgrade storage")
    func nonEntitlementFailureRemainsFatal() {
        let keychain = ScriptedMeetingKeychain(
            loads: [.init(status: errSecNotAvailable, data: nil)],
            adds: []
        )
        let store = KeychainMeetingPersistenceKeyStore(
            keychain: keychain,
            developmentFallback: InMemoryMeetingPersistenceKeyStore()
        )

        #expect(throws: MeetingPersistenceError.artifactUnreadable) {
            _ = try store.loadOrCreateKey()
        }
        #expect(keychain.loadUsesDataProtection == [true])
    }

    @Test("file fallback persists private key material without prompts")
    func fileFallbackPersistence() throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyURL = root.appendingPathComponent("meeting-key")
        let first = FileMeetingPersistenceKeyStore(fileURL: keyURL)

        let material = try first.loadOrCreateKey()
        let reloaded = try FileMeetingPersistenceKeyStore(fileURL: keyURL).loadOrCreateKey()

        #expect(reloaded == material)
        let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try Data(contentsOf: keyURL).count == 49)
    }

    @Test("empty meeting storage initializes with file fallback")
    func emptyStoreStartup() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
            .appendingPathComponent("Meetings", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let keychain = ScriptedMeetingKeychain(
            loads: [.init(status: errSecMissingEntitlement, data: nil)],
            adds: []
        )
        let store = MeetingSessionStore(
            rootURL: root,
            keyStore: KeychainMeetingPersistenceKeyStore(
                keychain: keychain,
                developmentFallback: FileMeetingPersistenceKeyStore(
                    fileURL: root.deletingLastPathComponent().appendingPathComponent("meeting-key")
                )
            )
        )

        let result = try await store.load()

        #expect(result.documents.isEmpty)
        #expect(result.issues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
    }
}

private final class ScriptedMeetingKeychain: MeetingPersistenceKeychainAccessing, @unchecked Sendable {
    struct LoadResult {
        let status: OSStatus
        let data: Data?
    }

    private let lock = NSLock()
    private var loads: [LoadResult]
    private var adds: [OSStatus]
    private(set) var loadUsesDataProtection: [Bool] = []
    private(set) var addUsesDataProtection: [Bool] = []

    init(loads: [LoadResult], adds: [OSStatus]) {
        self.loads = loads
        self.adds = adds
    }

    func load(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            loadUsesDataProtection.append(query[kSecUseDataProtectionKeychain as String] != nil)
            guard !loads.isEmpty else { return (errSecItemNotFound, nil) }
            let result = loads.removeFirst()
            return (result.status, result.data)
        }
    }

    func add(query: [String: Any]) -> OSStatus {
        lock.withLock {
            addUsesDataProtection.append(query[kSecUseDataProtectionKeychain as String] != nil)
            guard !adds.isEmpty else { return errSecParam }
            return adds.removeFirst()
        }
    }
}
