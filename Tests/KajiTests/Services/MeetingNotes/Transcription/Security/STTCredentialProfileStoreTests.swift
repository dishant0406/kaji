import Foundation
import Testing

@testable import Kaji

@Suite("STT credential profile security")
struct STTCredentialProfileStoreTests {
    @Test("in-memory Keychain abstraction keeps secrets out of metadata")
    func secretAndMetadataSeparation() throws {
        let secrets = InMemorySTTGenericPasswordStore()
        let metadataStore = InMemorySTTCredentialMetadataStore()
        let store = KeychainSTTCredentialProfileStore(secrets: secrets, metadata: metadataStore)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let profile = try STTCredentialProfileMetadata(
            providerID: "cloud-stt",
            displayName: "Work account",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let secret = Data("top-secret-api-key".utf8)

        try store.save(metadata: profile, secret: secret)

        #expect(try store.loadSecret(profileID: profile.id) == secret)
        #expect(try store.listMetadata() == [profile])
        let encodedMetadata = try JSONEncoder().encode(try store.listMetadata())
        #expect(!encodedMetadata.contains(secret))
    }

    @Test("save replaces a secret without duplicating metadata")
    func update() throws {
        let store = InMemorySTTCredentialProfileStore()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let profileID = UUID()
        let original = try STTCredentialProfileMetadata(
            id: profileID,
            providerID: "cloud-stt",
            displayName: "Original",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let updated = try STTCredentialProfileMetadata(
            id: profileID,
            providerID: "cloud-stt",
            displayName: "Updated",
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(10)
        )

        try store.save(metadata: original, secret: Data("first".utf8))
        try store.save(metadata: updated, secret: Data("second".utf8))

        #expect(try store.loadSecret(profileID: profileID) == Data("second".utf8))
        #expect(try store.listMetadata() == [updated])
    }

    @Test("delete removes metadata and secret")
    func delete() throws {
        let store = InMemorySTTCredentialProfileStore()
        let profile = try STTCredentialProfileMetadata(providerID: "cloud-stt", displayName: "Temporary")
        try store.save(metadata: profile, secret: Data("secret".utf8))

        try store.delete(profileID: profile.id)

        #expect(try store.listMetadata().isEmpty)
        #expect(throws: STTCredentialStoreError.credentialUnavailable) {
            try store.loadSecret(profileID: profile.id)
        }
    }

    @Test("metadata file never persists credential bytes")
    func fileMetadataExcludesSecret() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadataStore = FileSTTCredentialMetadataStore(fileURL: fileURL)
        let store = KeychainSTTCredentialProfileStore(
            secrets: InMemorySTTGenericPasswordStore(),
            metadata: metadataStore
        )
        let profile = try STTCredentialProfileMetadata(providerID: "cloud-stt", displayName: "Stored")
        let secret = Data("must-not-be-in-json".utf8)

        try store.save(metadata: profile, secret: secret)

        let persisted = try Data(contentsOf: fileURL)
        #expect(!persisted.contains(secret))
        #expect(try JSONDecoder().decode([STTCredentialProfileMetadata].self, from: persisted) == [profile])
        #expect(try permissions(at: directory) == 0o700)
        #expect(try permissions(at: fileURL) == 0o600)
    }

    @Test("metadata load repairs private permissions")
    func metadataPermissionRepair() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = try STTCredentialProfileMetadata(providerID: "cloud-stt", displayName: "Stored")
        try JSONEncoder().encode([profile]).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: fileURL.path)
        let store = FileSTTCredentialMetadataStore(fileURL: fileURL)

        #expect(try store.list() == [profile])
        #expect(try permissions(at: directory) == 0o700)
        #expect(try permissions(at: fileURL) == 0o600)
    }

    @Test("metadata load rejects symbolic link files and parents")
    func metadataSymlinkRejection() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let target = container.appendingPathComponent("target.json")
        try Data("[]".utf8).write(to: target)
        let linkedFile = container.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: target)

        #expect(throws: STTCredentialStoreError.operationFailed) {
            _ = try FileSTTCredentialMetadataStore(fileURL: linkedFile).list()
        }

        let targetDirectory = container.appendingPathComponent("target-directory", isDirectory: true)
        let linkedDirectory = container.appendingPathComponent("linked-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: targetDirectory)
        #expect(throws: STTCredentialStoreError.operationFailed) {
            _ = try FileSTTCredentialMetadataStore(
                fileURL: linkedDirectory.appendingPathComponent("profiles.json")
            ).list()
        }
    }

    @Test("invalid profile and secret values are rejected generically")
    func invalidValues() throws {
        #expect(throws: STTCredentialStoreError.invalidInput) {
            try STTCredentialProfileMetadata(providerID: "Cloud STT", displayName: "Profile")
        }
        let store = InMemorySTTCredentialProfileStore()
        let profile = try STTCredentialProfileMetadata(providerID: "cloud-stt", displayName: "Profile")
        #expect(throws: STTCredentialStoreError.invalidInput) {
            try store.save(metadata: profile, secret: Data())
        }

        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        object["apiKey"] = "must-be-rejected"
        let unknownFieldData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: STTCredentialStoreError.invalidInput) {
            try JSONDecoder().decode(STTCredentialProfileMetadata.self, from: unknownFieldData)
        }
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }
}
