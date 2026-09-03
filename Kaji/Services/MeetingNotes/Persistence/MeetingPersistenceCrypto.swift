import CryptoKit
import Foundation
import Security

struct MeetingPersistenceKeyMaterial: Equatable {
    let id: Data
    let key: Data

    init(id: Data, key: Data) throws {
        guard id.count == 16, key.count == 32 else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        self.id = id
        self.key = key
    }
}

protocol MeetingPersistenceKeyStoring: Sendable {
    func loadOrCreateKey() throws -> MeetingPersistenceKeyMaterial
}

protocol MeetingPersistenceKeychainAccessing: Sendable {
    func load(query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(query: [String: Any]) -> OSStatus
}

struct SecurityMeetingPersistenceKeychainAccess: MeetingPersistenceKeychainAccessing {
    func load(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    func add(query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }
}

final class FileMeetingPersistenceKeyStore: MeetingPersistenceKeyStoring, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        fileURL: URL = KajiFileStorage.fileURL(filename: "meeting-persistence-key-v2"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadOrCreateKey() throws -> MeetingPersistenceKeyMaterial {
        try lock.withLock {
            try secureParentDirectory()
            if fileManager.fileExists(atPath: fileURL.path) {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      ((attributes[.size] as? NSNumber)?.intValue ?? 0) == 49
                else {
                    throw MeetingPersistenceError.artifactUnreadable
                }
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                return try Self.decode(Data(contentsOf: fileURL, options: [.mappedIfSafe]))
            }
            let material = try MeetingPersistenceKeyMaterial(
                id: Self.randomData(byteCount: 16),
                key: Self.randomData(byteCount: 32)
            )
            try Self.encode(material).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return material
        }
    }

    private func secureParentDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) {
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingPersistenceError.artifactUnreadable
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func encode(_ material: MeetingPersistenceKeyMaterial) -> Data {
        Data([1]) + material.id + material.key
    }

    private static func decode(_ data: Data) throws -> MeetingPersistenceKeyMaterial {
        guard data.count == 49, data.first == 1 else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        return try MeetingPersistenceKeyMaterial(
            id: data.subdata(in: 1 ..< 17),
            key: data.subdata(in: 17 ..< 49)
        )
    }

    private static func randomData(byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
        }
        guard status == errSecSuccess else { throw MeetingPersistenceError.artifactUnreadable }
        return data
    }
}

final class KeychainMeetingPersistenceKeyStore: MeetingPersistenceKeyStoring, @unchecked Sendable {
    private static let service = "app.kaji.meeting-notes.persistence"
    private static let account = "aes-gcm-v2"
    private let lock = NSLock()
    private let keychain: any MeetingPersistenceKeychainAccessing
    private let developmentFallback: any MeetingPersistenceKeyStoring
    private var cachedMaterial: MeetingPersistenceKeyMaterial?

    init(
        keychain: any MeetingPersistenceKeychainAccessing = SecurityMeetingPersistenceKeychainAccess(),
        developmentFallback: any MeetingPersistenceKeyStoring = FileMeetingPersistenceKeyStore()
    ) {
        self.keychain = keychain
        self.developmentFallback = developmentFallback
    }

    func loadOrCreateKey() throws -> MeetingPersistenceKeyMaterial {
        try lock.withLock {
            if let cachedMaterial {
                return cachedMaterial
            }
            let loaded = keychain.load(query: loadQuery)
            if loaded.status == errSecSuccess, let data = loaded.data {
                return try remember(decode(data))
            }
            if loaded.status == errSecMissingEntitlement {
                return try remember(developmentFallback.loadOrCreateKey())
            }
            guard loaded.status == errSecItemNotFound else {
                throw MeetingPersistenceError.artifactUnreadable
            }
            let material = try MeetingPersistenceKeyMaterial(
                id: randomData(byteCount: 16),
                key: randomData(byteCount: 32)
            )
            let status = save(encode(material))
            if status == errSecSuccess {
                return remember(material)
            }
            if status == errSecMissingEntitlement {
                return try remember(developmentFallback.loadOrCreateKey())
            }
            if status == errSecDuplicateItem {
                let duplicate = keychain.load(query: loadQuery)
                guard duplicate.status == errSecSuccess, let data = duplicate.data else {
                    throw MeetingPersistenceError.artifactUnreadable
                }
                return try remember(decode(data))
            }
            throw MeetingPersistenceError.artifactUnreadable
        }
    }

    private func remember(_ material: MeetingPersistenceKeyMaterial) -> MeetingPersistenceKeyMaterial {
        cachedMaterial = material
        return material
    }

    private var loadQuery: [String: Any] {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func save(_ data: Data) -> OSStatus {
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return keychain.add(query: query)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
    }

    private func encode(_ material: MeetingPersistenceKeyMaterial) -> Data {
        Data([1]) + material.id + material.key
    }

    private func decode(_ data: Data) throws -> MeetingPersistenceKeyMaterial {
        guard data.count == 49, data.first == 1 else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        return try MeetingPersistenceKeyMaterial(
            id: data.subdata(in: 1 ..< 17),
            key: data.subdata(in: 17 ..< 49)
        )
    }

    private func randomData(byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
        }
        guard status == errSecSuccess else { throw MeetingPersistenceError.artifactUnreadable }
        return data
    }
}

final class InMemoryMeetingPersistenceKeyStore: MeetingPersistenceKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var material: MeetingPersistenceKeyMaterial?

    init(material: MeetingPersistenceKeyMaterial? = nil) {
        self.material = material
    }

    func loadOrCreateKey() throws -> MeetingPersistenceKeyMaterial {
        try lock.withLock {
            if let material {
                return material
            }
            let generated = try MeetingPersistenceKeyMaterial(
                id: Data(SHA256.hash(data: Data(UUID().uuidString.utf8)).prefix(16)),
                key: Data(SHA256.hash(data: Data((UUID().uuidString + UUID().uuidString).utf8)))
            )
            material = generated
            return generated
        }
    }

    func removeKey() {
        lock.withLock { material = nil }
    }

    func replaceKey() throws {
        lock.withLock { material = nil }
        _ = try loadOrCreateKey()
    }
}

struct MeetingPersistenceCrypto {
    static let envelopeOverhead = 53
    private static let magic = Data([0x4B, 0x41, 0x4A, 0x49, 0x4D, 0x54, 0x47, 0x32])
    private static let version: UInt8 = 2

    let keyStore: any MeetingPersistenceKeyStoring

    func seal(_ plaintext: Data, authenticatedData: Data) throws -> Data {
        let material = try keyStore.loadOrCreateKey()
        let key = SymmetricKey(data: material.key)
        do {
            let box = try AES.GCM.seal(plaintext, using: key, authenticating: authenticatedData)
            guard let combined = box.combined else { throw MeetingPersistenceError.writeFailed }
            return Self.magic + Data([Self.version]) + material.id + combined
        } catch let error as MeetingPersistenceError {
            throw error
        } catch {
            throw MeetingPersistenceError.writeFailed
        }
    }

    func open(_ envelope: Data, authenticatedData: Data, maximumPlaintextBytes: Int) throws -> Data {
        guard isEnvelope(envelope), envelope.count >= Self.envelopeOverhead else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        let versionOffset = Self.magic.count
        guard envelope[versionOffset] == Self.version else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        let keyIDRange = versionOffset + 1 ..< versionOffset + 17
        let combinedRange = versionOffset + 17 ..< envelope.count
        let material = try keyStore.loadOrCreateKey()
        guard envelope.subdata(in: keyIDRange) == material.id else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.subdata(in: combinedRange))
            let plaintext = try AES.GCM.open(
                box,
                using: SymmetricKey(data: material.key),
                authenticating: authenticatedData
            )
            guard plaintext.count <= maximumPlaintextBytes else {
                throw MeetingPersistenceError.artifactTooLarge
            }
            return plaintext
        } catch let error as MeetingPersistenceError {
            throw error
        } catch {
            throw MeetingPersistenceError.artifactUnreadable
        }
    }

    func isEnvelope(_ data: Data) -> Bool {
        data.count >= Self.magic.count && data.prefix(Self.magic.count) == Self.magic
    }

    static func sidecarAuthenticatedData(sessionID: UUID) -> Data {
        Data("KajiMeetingSidecar|2|\(sessionID.uuidString.lowercased())".utf8)
    }

    static var indexAuthenticatedData: Data {
        Data("KajiMeetingIndex|2".utf8)
    }
}
