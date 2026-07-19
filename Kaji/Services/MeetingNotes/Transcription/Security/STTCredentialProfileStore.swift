import Foundation
import Security

enum STTCredentialStoreError: Error, Equatable {
    case invalidInput
    case credentialUnavailable
    case operationFailed
}

struct STTCredentialProfileMetadata: Codable, Equatable, Identifiable {
    let id: UUID
    let providerID: String
    let displayName: String
    let endpointProfileID: UUID?
    let endpointOriginFingerprint: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        providerID: String,
        displayName: String,
        endpointProfileID: UUID? = nil,
        endpointOriginFingerprint: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidProviderID(normalizedProviderID),
              !normalizedDisplayName.isEmpty,
              normalizedDisplayName.count <= 120,
              !normalizedDisplayName.contains("\0"),
              endpointOriginFingerprint.map(Self.isValidFingerprint) ?? true,
              (endpointProfileID == nil) == (endpointOriginFingerprint == nil),
              createdAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= createdAt
        else {
            throw STTCredentialStoreError.invalidInput
        }
        self.id = id
        self.providerID = normalizedProviderID
        self.displayName = normalizedDisplayName
        self.endpointProfileID = endpointProfileID
        self.endpointOriginFingerprint = endpointOriginFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: STTCredentialMetadataCodingKey.self)
        let allowedKeys = Set([
            "id", "providerID", "displayName", "endpointProfileID", "endpointOriginFingerprint", "createdAt", "updatedAt",
        ])
        guard Set(container.allKeys.map(\.stringValue)).isSubset(of: allowedKeys) else {
            throw STTCredentialStoreError.invalidInput
        }
        try self.init(
            id: container.decode(UUID.self, forKey: .init("id")),
            providerID: container.decode(String.self, forKey: .init("providerID")),
            displayName: container.decode(String.self, forKey: .init("displayName")),
            endpointProfileID: container.decodeIfPresent(UUID.self, forKey: .init("endpointProfileID")),
            endpointOriginFingerprint: container.decodeIfPresent(String.self, forKey: .init("endpointOriginFingerprint")),
            createdAt: container.decode(Date.self, forKey: .init("createdAt")),
            updatedAt: container.decode(Date.self, forKey: .init("updatedAt"))
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: STTCredentialMetadataCodingKey.self)
        try container.encode(id, forKey: .init("id"))
        try container.encode(providerID, forKey: .init("providerID"))
        try container.encode(displayName, forKey: .init("displayName"))
        try container.encodeIfPresent(endpointProfileID, forKey: .init("endpointProfileID"))
        try container.encodeIfPresent(endpointOriginFingerprint, forKey: .init("endpointOriginFingerprint"))
        try container.encode(createdAt, forKey: .init("createdAt"))
        try container.encode(updatedAt, forKey: .init("updatedAt"))
    }

    private static func isValidProviderID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.utf8.allSatisfy { byte in
            byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 ||
                byte == 0x2D || byte == 0x2E || byte == 0x5F
        }
    }

    private static func isValidFingerprint(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

private struct STTCredentialMetadataCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

protocol STTCredentialProfileStoring: Sendable {
    func save(metadata: STTCredentialProfileMetadata, secret: Data) throws
    func loadSecret(profileID: UUID) throws -> Data
    func delete(profileID: UUID) throws
    func listMetadata() throws -> [STTCredentialProfileMetadata]
}

protocol STTGenericPasswordStoring: Sendable {
    func save(secret: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

protocol STTCredentialMetadataStoring: Sendable {
    func save(_ metadata: STTCredentialProfileMetadata) throws
    func delete(profileID: UUID) throws
    func list() throws -> [STTCredentialProfileMetadata]
}

final class KeychainSTTCredentialProfileStore: STTCredentialProfileStoring, @unchecked Sendable {
    static let service = "app.kaji.meeting-transcription"
    static let maximumSecretBytes = 16 * 1024

    private let secrets: any STTGenericPasswordStoring
    private let metadata: any STTCredentialMetadataStoring
    private let lock = NSLock()

    init(
        secrets: any STTGenericPasswordStoring = SecurityGenericPasswordStore(),
        metadata: any STTCredentialMetadataStoring
    ) {
        self.secrets = secrets
        self.metadata = metadata
    }

    func save(metadata profile: STTCredentialProfileMetadata, secret: Data) throws {
        guard !secret.isEmpty, secret.count <= Self.maximumSecretBytes else {
            throw STTCredentialStoreError.invalidInput
        }
        try lock.withLock {
            let account = profile.id.uuidString.lowercased()
            let previousSecret = try generic { try secrets.load(account: account) }
            do {
                try generic { try secrets.save(secret: secret, account: account) }
                try generic { try metadata.save(profile) }
            } catch {
                if let previousSecret {
                    try? secrets.save(secret: previousSecret, account: account)
                } else {
                    try? secrets.delete(account: account)
                }
                throw STTCredentialStoreError.operationFailed
            }
        }
    }

    func loadSecret(profileID: UUID) throws -> Data {
        try lock.withLock {
            let secret = try generic {
                try secrets.load(account: profileID.uuidString.lowercased())
            }
            guard let secret else { throw STTCredentialStoreError.credentialUnavailable }
            return secret
        }
    }

    func delete(profileID: UUID) throws {
        try lock.withLock {
            let account = profileID.uuidString.lowercased()
            let previousSecret = try generic { try secrets.load(account: account) }
            do {
                try generic { try secrets.delete(account: account) }
                try generic { try metadata.delete(profileID: profileID) }
            } catch {
                if let previousSecret {
                    try? secrets.save(secret: previousSecret, account: account)
                }
                throw STTCredentialStoreError.operationFailed
            }
        }
    }

    func listMetadata() throws -> [STTCredentialProfileMetadata] {
        try lock.withLock {
            try generic { try metadata.list() }
                .sorted { left, right in
                    if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
                    return left.id.uuidString < right.id.uuidString
                }
        }
    }

    private func generic<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as STTCredentialStoreError {
            throw error
        } catch {
            throw STTCredentialStoreError.operationFailed
        }
    }
}

final class SecurityGenericPasswordStore: STTGenericPasswordStoring, @unchecked Sendable {
    func save(secret: Data, account: String) throws {
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw STTCredentialStoreError.operationFailed
        }
        attributes.forEach { query[$0.key] = $0.value }
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw STTCredentialStoreError.operationFailed
        }
    }

    func load(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw STTCredentialStoreError.operationFailed
        }
        let attributes = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        guard SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary) == errSecSuccess else {
            throw STTCredentialStoreError.operationFailed
        }
        return data
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw STTCredentialStoreError.operationFailed
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainSTTCredentialProfileStore.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
    }
}

final class InMemorySTTGenericPasswordStore: STTGenericPasswordStoring, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func save(secret: Data, account: String) {
        lock.withLock { values[account] = secret }
    }

    func load(account: String) -> Data? {
        lock.withLock { values[account] }
    }

    func delete(account: String) {
        lock.withLock { _ = values.removeValue(forKey: account) }
    }
}

final class InMemorySTTCredentialMetadataStore: STTCredentialMetadataStoring, @unchecked Sendable {
    private var values: [UUID: STTCredentialProfileMetadata] = [:]
    private let lock = NSLock()

    func save(_ metadata: STTCredentialProfileMetadata) {
        lock.withLock { values[metadata.id] = metadata }
    }

    func delete(profileID: UUID) {
        lock.withLock { _ = values.removeValue(forKey: profileID) }
    }

    func list() -> [STTCredentialProfileMetadata] {
        lock.withLock { Array(values.values) }
    }
}

final class InMemorySTTCredentialProfileStore: STTCredentialProfileStoring, @unchecked Sendable {
    private let store: KeychainSTTCredentialProfileStore

    init() {
        store = KeychainSTTCredentialProfileStore(
            secrets: InMemorySTTGenericPasswordStore(),
            metadata: InMemorySTTCredentialMetadataStore()
        )
    }

    func save(metadata: STTCredentialProfileMetadata, secret: Data) throws {
        try store.save(metadata: metadata, secret: secret)
    }

    func loadSecret(profileID: UUID) throws -> Data {
        try store.loadSecret(profileID: profileID)
    }

    func delete(profileID: UUID) throws {
        try store.delete(profileID: profileID)
    }

    func listMetadata() throws -> [STTCredentialProfileMetadata] {
        try store.listMetadata()
    }
}

final class FileSTTCredentialMetadataStore: STTCredentialMetadataStoring, @unchecked Sendable {
    static let maximumFileBytes = 256 * 1024

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func save(_ metadata: STTCredentialProfileMetadata) throws {
        try lock.withLock {
            var values = try loadUnlocked()
            values.removeAll { $0.id == metadata.id }
            values.append(metadata)
            try writeUnlocked(values)
        }
    }

    func delete(profileID: UUID) throws {
        try lock.withLock {
            var values = try loadUnlocked()
            values.removeAll { $0.id == profileID }
            try writeUnlocked(values)
        }
    }

    func list() throws -> [STTCredentialProfileMetadata] {
        try lock.withLock { try loadUnlocked() }
    }

    private func loadUnlocked() throws -> [STTCredentialProfileMetadata] {
        try secureParentDirectory()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= Self.maximumFileBytes
        else {
            throw STTCredentialStoreError.operationFailed
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let values = try JSONDecoder().decode([STTCredentialProfileMetadata].self, from: data)
        guard Set(values.map(\.id)).count == values.count else {
            throw STTCredentialStoreError.operationFailed
        }
        return values
    }

    private func writeUnlocked(_ values: [STTCredentialProfileMetadata]) throws {
        try secureParentDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw STTCredentialStoreError.operationFailed
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(values)
        guard data.count <= Self.maximumFileBytes else {
            throw STTCredentialStoreError.operationFailed
        }
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func secureParentDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw STTCredentialStoreError.operationFailed
            }
        } else {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw STTCredentialStoreError.operationFailed
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
