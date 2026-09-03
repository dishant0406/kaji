import Foundation

enum MeetingPersistenceError: Error, Equatable {
    case artifactTooLarge
    case invalidDocument
    case sessionPinned
    case sessionNotTerminal
    case artifactUnreadable
    case writeFailed
}

enum MeetingLoadIssueKind: String, Codable {
    case malformedIndex
    case malformedSidecar
    case oversizedSidecar
    case invalidSidecarName
    case missingSidecar
    case sidecarIDMismatch
    case invalidDocument
}

struct MeetingLoadIssue: Codable, Equatable {
    let kind: MeetingLoadIssueKind
    let artifactName: String
}

struct MeetingLoadResult {
    var documents: [MeetingSessionDocument]
    let issues: [MeetingLoadIssue]
}

struct MeetingRetentionResult: Equatable {
    let deletedSessionIDs: [UUID]
    let protectedSessionIDs: [UUID]
    let rawAudioDeletedSessionIDs: [UUID]
}

struct MeetingFinalizationResult: Equatable {
    let document: MeetingSessionDocument
    let retention: MeetingRetentionResult
}

struct MeetingPersistenceLimits {
    var maximumIndexBytes = 32 * 1024 * 1024
    var maximumSidecarBytes = 256 * 1024 * 1024
    var maximumAudioArtifactBytes = 64 * 1024 * 1024
}

private struct MeetingSessionIndex: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    var sessions: [MeetingSessionIndexEntry]
}

private struct MeetingSessionIndexEntry: Codable, Equatable {
    let id: UUID
    let title: String
    let phase: MeetingLifecyclePhase
    let updatedAtMilliseconds: Int64
    let isPinned: Bool
    let projectIDs: [UUID]
}

private struct MeetingDiskState {
    var documents: [MeetingSessionDocument]
    let issues: [MeetingLoadIssue]
    let indexedIDs: Set<UUID>
    let sidecarIDs: Set<UUID>
    let audioIDs: Set<UUID>
}

actor MeetingSessionStore {
    let rootURL: URL
    private let fileManager: FileManager
    private let validator: MeetingDocumentValidator
    private let limits: MeetingPersistenceLimits
    private let crypto: MeetingPersistenceCrypto

    init(
        rootURL: URL = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("Meetings", isDirectory: true),
        fileManager: FileManager = .default,
        validator: MeetingDocumentValidator = MeetingDocumentValidator(),
        limits: MeetingPersistenceLimits = MeetingPersistenceLimits(),
        keyStore: any MeetingPersistenceKeyStoring = KeychainMeetingPersistenceKeyStore()
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.validator = validator
        self.limits = limits
        crypto = MeetingPersistenceCrypto(keyStore: keyStore)
    }

    func save(_ document: MeetingSessionDocument) throws {
        try validate(document)
        try prepareDirectories()
        try resumePendingDeletions()
        var state = try scanDisk(tombstonedIDs: [])
        state.documents.removeAll { $0.session.id == document.session.id }
        state.documents.append(document)
        let sidecarData = try encodedJSON(document, maximumBytes: limits.maximumSidecarBytes)
        let indexData = try encodedIndex(for: state.documents)
        try writeEncryptedData(
            sidecarData,
            to: sidecarURL(for: document.session.id),
            authenticatedData: MeetingPersistenceCrypto.sidecarAuthenticatedData(sessionID: document.session.id)
        )
        try writeEncryptedData(indexData, to: indexURL, authenticatedData: MeetingPersistenceCrypto.indexAuthenticatedData)
    }

    func load() throws -> MeetingLoadResult {
        try prepareDirectories()
        try resumePendingDeletions()
        let state = try scanDisk(tombstonedIDs: [])
        try writeIndex(for: state.documents)
        return MeetingLoadResult(documents: state.documents, issues: state.issues)
    }

    func recoverStaleSessions(
        nowMilliseconds: Int64,
        staleAfterMilliseconds: Int64,
        reason: String = "Recording was interrupted before the session completed."
    ) throws -> [UUID] {
        guard nowMilliseconds >= 0, staleAfterMilliseconds >= 0 else {
            throw MeetingPersistenceError.invalidDocument
        }
        try prepareDirectories()
        try resumePendingDeletions()
        var state = try scanDisk(tombstonedIDs: [])
        var recovered: [UUID] = []
        for index in state.documents.indices {
            let session = state.documents[index].session
            guard session.lifecycle.phase.isActive,
                  session.updatedAtMilliseconds <= nowMilliseconds,
                  nowMilliseconds - session.updatedAtMilliseconds >= staleAfterMilliseconds
            else {
                continue
            }
            try state.documents[index].session.transition(
                to: .interrupted,
                atMilliseconds: nowMilliseconds,
                interruptionReason: reason
            )
            recovered.append(session.id)
        }
        guard !recovered.isEmpty else { return [] }
        let recoveredIDs = Set(recovered)
        let encodedDocuments = try state.documents.compactMap { document -> (UUID, Data)? in
            guard recoveredIDs.contains(document.session.id) else { return nil }
            return try (
                document.session.id,
                encodedJSON(document, maximumBytes: limits.maximumSidecarBytes)
            )
        }
        let indexData = try encodedIndex(for: state.documents)
        for (id, data) in encodedDocuments {
            try writeEncryptedData(
                data,
                to: sidecarURL(for: id),
                authenticatedData: MeetingPersistenceCrypto.sidecarAuthenticatedData(sessionID: id)
            )
        }
        try writeEncryptedData(indexData, to: indexURL, authenticatedData: MeetingPersistenceCrypto.indexAuthenticatedData)
        return recovered.sorted { $0.uuidString < $1.uuidString }
    }

    func deleteSession(id: UUID, includingPinned: Bool = false) throws -> Bool {
        try prepareDirectories()
        try resumePendingDeletions()
        let state = try scanDisk(tombstonedIDs: [])
        let document = state.documents.first { $0.session.id == id }
        if let document, document.session.isPinned, !includingPinned {
            throw MeetingPersistenceError.sessionPinned
        }
        let existed = state.sidecarIDs.contains(id) ||
            state.audioIDs.contains(id) ||
            state.indexedIDs.contains(id) ||
            itemExists(tombstoneURL(for: id))
        guard existed else { return false }
        try createTombstone(for: id)
        var failed = false
        do {
            try writeIndex(for: state.documents.filter { $0.session.id != id })
        } catch {
            failed = true
        }
        if !cleanupArtifacts(for: id) {
            failed = true
        }
        if !failed {
            do {
                try removeIfPresent(tombstoneURL(for: id))
            } catch {
                failed = true
            }
        }
        if failed {
            throw MeetingPersistenceError.writeFailed
        }
        return true
    }

    func finalize(
        _ document: MeetingSessionDocument,
        settings: MeetingNotesSettings = .privacyDefaults
    ) throws -> MeetingSessionDocument {
        guard document.session.lifecycle.phase.isTerminal else {
            throw MeetingPersistenceError.sessionNotTerminal
        }
        try validate(document)
        try save(document)
        guard !settings.retainRawAudio else { return document }
        try removeIfPresent(audioDirectory(for: document.session.id))
        var finalized = document
        for index in finalized.audioChunks.indices where finalized.audioChunks[index].storageState == .stored {
            finalized.audioChunks[index].storageState = .deleted
        }
        try save(finalized)
        return finalized
    }

    func finalizeAndEnforceRetention(
        _ document: MeetingSessionDocument,
        settings: MeetingNotesSettings = .privacyDefaults,
        nowMilliseconds: Int64
    ) throws -> MeetingFinalizationResult {
        let finalized = try finalize(document, settings: settings)
        let retention = try enforceRetention(settings: settings, nowMilliseconds: nowMilliseconds)
        return MeetingFinalizationResult(document: finalized, retention: retention)
    }

    func enforceRetention(
        settings: MeetingNotesSettings = .privacyDefaults,
        nowMilliseconds: Int64
    ) throws -> MeetingRetentionResult {
        guard nowMilliseconds >= 0 else { throw MeetingPersistenceError.invalidDocument }
        try prepareDirectories()
        try resumePendingDeletions()
        let state = try scanDisk(tombstonedIDs: [])
        let validIDs = Set(state.documents.map(\.session.id))
        let retentionMilliseconds = Int64(settings.retentionDays) * 86_400_000
        let cutoff = max(0, nowMilliseconds - retentionMilliseconds)
        var deletionIDs = state.sidecarIDs.subtracting(validIDs)
        deletionIDs.formUnion(state.audioIDs.subtracting(validIDs))
        var protectedIDs: Set<UUID> = []
        var retained: [MeetingSessionDocument] = []
        for document in state.documents {
            let session = document.session
            let expired = session.lifecycle.phase.isTerminal && session.updatedAtMilliseconds <= cutoff
            if expired, session.isPinned {
                protectedIDs.insert(session.id)
                retained.append(document)
            } else if expired {
                deletionIDs.insert(session.id)
            } else {
                retained.append(document)
            }
        }

        var failed = false
        var tombstonedIDs: Set<UUID> = []
        for id in deletionIDs {
            do {
                try createTombstone(for: id)
                tombstonedIDs.insert(id)
            } catch {
                failed = true
            }
        }
        do {
            try writeIndex(for: retained)
        } catch {
            failed = true
        }

        var cleanedDeletionIDs: Set<UUID> = []
        var rawAudioDeletedIDs: Set<UUID> = []
        for id in tombstonedIDs {
            let hadAudio = state.audioIDs.contains(id) || itemExists(audioDirectory(for: id))
            if cleanupArtifacts(for: id) {
                cleanedDeletionIDs.insert(id)
                if hadAudio {
                    rawAudioDeletedIDs.insert(id)
                }
            } else {
                failed = true
            }
        }

        if !settings.retainRawAudio {
            for index in retained.indices where retained[index].session.lifecycle.phase.isTerminal {
                let id = retained[index].session.id
                let audioDirectoryExists = itemExists(audioDirectory(for: id))
                do {
                    try removeIfPresent(audioDirectory(for: id))
                    if audioDirectoryExists {
                        rawAudioDeletedIDs.insert(id)
                    }
                    var changed = false
                    for chunkIndex in retained[index].audioChunks.indices
                        where retained[index].audioChunks[chunkIndex].storageState == .stored
                    {
                        retained[index].audioChunks[chunkIndex].storageState = .deleted
                        changed = true
                    }
                    if changed {
                        try writeDocument(retained[index])
                    }
                } catch {
                    failed = true
                }
            }
        }

        var indexWritten = false
        do {
            try writeIndex(for: retained)
            indexWritten = true
        } catch {
            failed = true
        }
        if indexWritten {
            for id in cleanedDeletionIDs {
                do {
                    try removeIfPresent(tombstoneURL(for: id))
                } catch {
                    failed = true
                }
            }
        }
        if failed {
            throw MeetingPersistenceError.writeFailed
        }
        return MeetingRetentionResult(
            deletedSessionIDs: cleanedDeletionIDs.sorted { $0.uuidString < $1.uuidString },
            protectedSessionIDs: protectedIDs.sorted { $0.uuidString < $1.uuidString },
            rawAudioDeletedSessionIDs: rawAudioDeletedIDs.sorted { $0.uuidString < $1.uuidString }
        )
    }

    func writeRawAudio(
        _ data: Data,
        sessionID: UUID,
        chunkID: UUID,
        encoding: MeetingAudioEncoding
    ) throws -> URL {
        guard !data.isEmpty, data.count <= limits.maximumAudioArtifactBytes else {
            throw MeetingPersistenceError.artifactTooLarge
        }
        try prepareDirectories()
        try resumePendingDeletions()
        let directory = audioDirectory(for: sessionID)
        try ensureSecureDirectory(directory)
        let url = audioArtifactURL(sessionID: sessionID, chunkID: chunkID, encoding: encoding)
        try writeSecureData(data, to: url)
        return url
    }

    func deleteRawAudio(sessionID: UUID) throws -> Bool {
        let directory = audioDirectory(for: sessionID)
        guard itemExists(directory) else { return false }
        try removeIfPresent(directory)
        return true
    }

    func audioArtifactURL(sessionID: UUID, chunkID: UUID, encoding: MeetingAudioEncoding) -> URL {
        audioDirectory(for: sessionID)
            .appendingPathComponent("\(chunkID.uuidString).\(encoding.fileExtension)", isDirectory: false)
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json", isDirectory: false)
    }

    private var sessionsURL: URL {
        rootURL.appendingPathComponent("Sessions", isDirectory: true)
    }

    private var audioURL: URL {
        rootURL.appendingPathComponent("Audio", isDirectory: true)
    }

    private var tombstonesURL: URL {
        rootURL.appendingPathComponent("DeletionTombstones", isDirectory: true)
    }

    private func sidecarURL(for id: UUID) -> URL {
        sessionsURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func audioDirectory(for id: UUID) -> URL {
        audioURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func tombstoneURL(for id: UUID) -> URL {
        tombstonesURL.appendingPathComponent("\(id.uuidString).tombstone", isDirectory: false)
    }

    private func prepareDirectories() throws {
        try ensureSecureDirectory(rootURL)
        try ensureSecureDirectory(sessionsURL)
        try ensureSecureDirectory(audioURL)
        try ensureSecureDirectory(tombstonesURL)
    }

    private func ensureSecureDirectory(_ url: URL) throws {
        if itemExists(url) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingPersistenceError.artifactUnreadable
            }
        } else {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func resumePendingDeletions() throws {
        let ids = try pendingDeletionIDs()
        guard !ids.isEmpty else { return }
        var cleaned: Set<UUID> = []
        for id in ids where cleanupArtifacts(for: id) {
            cleaned.insert(id)
        }
        let state = try scanDisk(tombstonedIDs: ids)
        try writeIndex(for: state.documents)
        for id in cleaned {
            try removeIfPresent(tombstoneURL(for: id))
        }
    }

    private func pendingDeletionIDs() throws -> Set<UUID> {
        let urls = try fileManager.contentsOfDirectory(
            at: tombstonesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return Set(urls.compactMap { url in
            guard url.pathExtension == "tombstone" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        })
    }

    private func scanDisk(tombstonedIDs: Set<UUID>) throws -> MeetingDiskState {
        var issues: [MeetingLoadIssue] = []
        let indexedIDs = try readIndex(issues: &issues)
        let sidecarURLs = try fileManager.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var urlsByID: [UUID: URL] = [:]
        for url in sidecarURLs where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                issues.append(.init(kind: .invalidSidecarName, artifactName: url.lastPathComponent))
                continue
            }
            urlsByID[id] = url
        }
        for id in indexedIDs where urlsByID[id] == nil && !tombstonedIDs.contains(id) {
            issues.append(.init(kind: .missingSidecar, artifactName: "\(id.uuidString).json"))
        }
        var documents: [MeetingSessionDocument] = []
        for id in urlsByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) where !tombstonedIDs.contains(id) {
            guard let url = urlsByID[id] else { continue }
            do {
                guard let loaded = try loadDocument(at: url, sessionID: id) else {
                    issues.append(.init(kind: .malformedSidecar, artifactName: url.lastPathComponent))
                    continue
                }
                let document = loaded.document
                guard document.session.id == id else {
                    issues.append(.init(kind: .sidecarIDMismatch, artifactName: url.lastPathComponent))
                    continue
                }
                do {
                    try validator.validate(document)
                } catch {
                    issues.append(.init(kind: .invalidDocument, artifactName: url.lastPathComponent))
                    continue
                }
                documents.append(document)
                if loaded.requiresMigration {
                    try writeDocument(document)
                }
            } catch MeetingPersistenceError.artifactTooLarge {
                issues.append(.init(kind: .oversizedSidecar, artifactName: url.lastPathComponent))
            }
        }
        documents.sort(by: documentOrdering)
        let audioIDs = try artifactIDs(in: audioURL)
        return MeetingDiskState(
            documents: documents,
            issues: issues,
            indexedIDs: indexedIDs,
            sidecarIDs: Set(urlsByID.keys),
            audioIDs: audioIDs
        )
    }

    private func artifactIDs(in directory: URL) throws -> Set<UUID> {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return Set(urls.compactMap { UUID(uuidString: $0.lastPathComponent) })
    }

    private func readIndex(issues: inout [MeetingLoadIssue]) throws -> Set<UUID> {
        guard itemExists(indexURL) else { return [] }
        do {
            let data = try readProtectedData(
                at: indexURL,
                maximumBytes: limits.maximumIndexBytes,
                authenticatedData: MeetingPersistenceCrypto.indexAuthenticatedData
            ).data
            let index = try JSONDecoder().decode(MeetingSessionIndex.self, from: data)
            guard index.version == MeetingSessionIndex.currentVersion else {
                issues.append(.init(kind: .malformedIndex, artifactName: indexURL.lastPathComponent))
                return []
            }
            return Set(index.sessions.map(\.id))
        } catch MeetingPersistenceError.artifactUnreadable {
            if try sessionsDirectoryHasNoSidecars() {
                issues.append(.init(kind: .malformedIndex, artifactName: indexURL.lastPathComponent))
                return []
            }
            throw MeetingPersistenceError.artifactUnreadable
        } catch {
            issues.append(.init(kind: .malformedIndex, artifactName: indexURL.lastPathComponent))
            return []
        }
    }

    private func sessionsDirectoryHasNoSidecars() throws -> Bool {
        let urls = try fileManager.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return !urls.contains { $0.pathExtension == "json" }
    }

    private func loadDocument(
        at url: URL,
        sessionID: UUID
    ) throws -> (document: MeetingSessionDocument, requiresMigration: Bool)? {
        do {
            let protected = try readProtectedData(
                at: url,
                maximumBytes: limits.maximumSidecarBytes,
                authenticatedData: MeetingPersistenceCrypto.sidecarAuthenticatedData(sessionID: sessionID)
            )
            return try (
                JSONDecoder().decode(MeetingSessionDocument.self, from: protected.data),
                protected.requiresMigration
            )
        } catch MeetingPersistenceError.artifactTooLarge {
            throw MeetingPersistenceError.artifactTooLarge
        } catch MeetingPersistenceError.artifactUnreadable {
            throw MeetingPersistenceError.artifactUnreadable
        } catch {
            return nil
        }
    }

    private func readProtectedData(
        at url: URL,
        maximumBytes: Int,
        authenticatedData: Data
    ) throws -> (data: Data, requiresMigration: Bool) {
        let raw = try readData(
            at: url,
            maximumBytes: maximumBytes + MeetingPersistenceCrypto.envelopeOverhead
        )
        guard crypto.isEnvelope(raw) else {
            guard raw.count <= maximumBytes else { throw MeetingPersistenceError.artifactTooLarge }
            return (raw, true)
        }
        return try (
            crypto.open(raw, authenticatedData: authenticatedData, maximumPlaintextBytes: maximumBytes),
            false
        )
    }

    private func readData(at url: URL, maximumBytes: Int) throws -> Data {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MeetingPersistenceError.artifactUnreadable
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumBytes else { throw MeetingPersistenceError.artifactTooLarge }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else { throw MeetingPersistenceError.artifactTooLarge }
        return data
    }

    private func writeDocument(_ document: MeetingSessionDocument) throws {
        let data = try encodedJSON(document, maximumBytes: limits.maximumSidecarBytes)
        try writeEncryptedData(
            data,
            to: sidecarURL(for: document.session.id),
            authenticatedData: MeetingPersistenceCrypto.sidecarAuthenticatedData(sessionID: document.session.id)
        )
    }

    private func writeIndex(for documents: [MeetingSessionDocument]) throws {
        try writeEncryptedData(
            encodedIndex(for: documents),
            to: indexURL,
            authenticatedData: MeetingPersistenceCrypto.indexAuthenticatedData
        )
    }

    private func encodedIndex(for documents: [MeetingSessionDocument]) throws -> Data {
        let entries = documents.map { document in
            MeetingSessionIndexEntry(
                id: document.session.id,
                title: document.session.title,
                phase: document.session.lifecycle.phase,
                updatedAtMilliseconds: document.session.updatedAtMilliseconds,
                isPinned: document.session.isPinned,
                projectIDs: document.session.projectIDs
            )
        }.sorted {
            if $0.updatedAtMilliseconds == $1.updatedAtMilliseconds {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.updatedAtMilliseconds > $1.updatedAtMilliseconds
        }
        return try encodedJSON(
            MeetingSessionIndex(version: MeetingSessionIndex.currentVersion, sessions: entries),
            maximumBytes: limits.maximumIndexBytes
        )
    }

    private func encodedJSON(_ value: some Encodable, maximumBytes: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw MeetingPersistenceError.artifactTooLarge }
        return data
    }

    private func writeSecureData(_ data: Data, to url: URL) throws {
        if itemExists(url) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw MeetingPersistenceError.writeFailed
            }
        }
        do {
            try data.write(to: url, options: .atomic)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw MeetingPersistenceError.writeFailed
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch let error as MeetingPersistenceError {
            throw error
        } catch {
            throw MeetingPersistenceError.writeFailed
        }
    }

    private func writeEncryptedData(_ data: Data, to url: URL, authenticatedData: Data) throws {
        try writeSecureData(crypto.seal(data, authenticatedData: authenticatedData), to: url)
    }

    private func createTombstone(for id: UUID) throws {
        try writeSecureData(Data(id.uuidString.utf8), to: tombstoneURL(for: id))
    }

    private func cleanupArtifacts(for id: UUID) -> Bool {
        var succeeded = true
        do {
            try removeIfPresent(sidecarURL(for: id))
        } catch {
            succeeded = false
        }
        do {
            try removeIfPresent(audioDirectory(for: id))
        } catch {
            succeeded = false
        }
        return succeeded
    }

    private func removeIfPresent(_ url: URL) throws {
        guard itemExists(url) else { return }
        try fileManager.removeItem(at: url)
    }

    private func itemExists(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private func validate(_ document: MeetingSessionDocument) throws {
        do {
            try validator.validate(document)
        } catch {
            throw MeetingPersistenceError.invalidDocument
        }
    }

    private func documentOrdering(_ lhs: MeetingSessionDocument, _ rhs: MeetingSessionDocument) -> Bool {
        if lhs.session.updatedAtMilliseconds == rhs.session.updatedAtMilliseconds {
            return lhs.session.id.uuidString < rhs.session.id.uuidString
        }
        return lhs.session.updatedAtMilliseconds > rhs.session.updatedAtMilliseconds
    }
}
