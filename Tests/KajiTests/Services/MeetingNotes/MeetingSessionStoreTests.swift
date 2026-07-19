import Foundation
import Testing

@testable import Kaji

@Suite("Meeting session persistence")
struct MeetingSessionStoreTests {
    @Test("store round-trips sidecars and enforces private permissions")
    func persistenceRoundTripAndPermissions() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
            .appendingPathComponent("Meetings", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = MeetingSessionStore(rootURL: root, keyStore: InMemoryMeetingPersistenceKeyStore())
        let document = try MeetingNotesTestFixtures.document()

        try await store.save(document)
        let loaded = try await store.load()

        #expect(loaded.documents == [document])
        #expect(loaded.issues.isEmpty)
        let sidecar = root
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent("\(document.session.id.uuidString).json")
        let index = root.appendingPathComponent("index.json")
        #expect(try permissions(at: root) == 0o700)
        #expect(try permissions(at: root.appendingPathComponent("Sessions", isDirectory: true)) == 0o700)
        #expect(try permissions(at: sidecar) == 0o600)
        #expect(try permissions(at: index) == 0o600)
        let sidecarData = try Data(contentsOf: sidecar)
        let indexData = try Data(contentsOf: index)
        #expect(sidecarData.starts(with: Data("KAJIMTG2".utf8)))
        #expect(indexData.starts(with: Data("KAJIMTG2".utf8)))
        #expect(!sidecarData.contains(Data(document.session.title.utf8)))
        #expect(!indexData.contains(Data(document.session.title.utf8)))
    }

    @Test("stale active sessions recover to interrupted while fresh sessions remain active")
    func staleRecovery() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(
            rootURL: root.appendingPathComponent("Meetings"),
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let stale = try MeetingNotesTestFixtures.document(
            phase: .recording,
            updatedAtMilliseconds: 1_100
        )
        let fresh = try MeetingNotesTestFixtures.document(
            phase: .paused,
            updatedAtMilliseconds: 9_500
        )
        try await store.save(stale)
        try await store.save(fresh)

        let recovered = try await store.recoverStaleSessions(
            nowMilliseconds: 10_000,
            staleAfterMilliseconds: 1_000
        )
        let loaded = try await store.load()
        let staleAfter = try #require(loaded.documents.first { $0.session.id == stale.session.id })
        let freshAfter = try #require(loaded.documents.first { $0.session.id == fresh.session.id })

        #expect(recovered == [stale.session.id])
        #expect(staleAfter.session.lifecycle.phase == .interrupted)
        #expect(staleAfter.session.lifecycle.endedAtMilliseconds == 10_000)
        #expect(freshAfter.session.lifecycle.phase == .paused)
    }

    @Test("retention deletes expired sessions and raw audio but protects pinned sessions")
    func retentionAndPinProtection() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(
            rootURL: root.appendingPathComponent("Meetings"),
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let expired = try MeetingNotesTestFixtures.document(phase: .completed)
        let pinned = try MeetingNotesTestFixtures.document(phase: .completed, isPinned: true)
        try await store.save(expired)
        try await store.save(pinned)
        let expiredAudio = try await store.writeRawAudio(
            Data([1, 2, 3]),
            sessionID: expired.session.id,
            chunkID: UUID(),
            encoding: .caf
        )
        let pinnedAudio = try await store.writeRawAudio(
            Data([4, 5, 6]),
            sessionID: pinned.session.id,
            chunkID: UUID(),
            encoding: .wav
        )

        let result = try await store.enforceRetention(
            settings: .privacyDefaults,
            nowMilliseconds: 31 * 86_400_000
        )
        let loaded = try await store.load()

        #expect(result.deletedSessionIDs == [expired.session.id])
        #expect(result.protectedSessionIDs == [pinned.session.id])
        #expect(Set(result.rawAudioDeletedSessionIDs) == [expired.session.id, pinned.session.id])
        #expect(loaded.documents.map(\.session.id) == [pinned.session.id])
        #expect(!FileManager.default.fileExists(atPath: expiredAudio.path))
        #expect(!FileManager.default.fileExists(atPath: pinnedAudio.path))
        do {
            _ = try await store.deleteSession(id: pinned.session.id)
            Issue.record("Expected pinned session deletion to fail")
        } catch {
            #expect(error as? MeetingPersistenceError == .sessionPinned)
        }
        #expect(try await store.deleteSession(id: pinned.session.id, includingPinned: true))
        #expect(try await store.load().documents.isEmpty)
    }

    @Test("finalization deletes raw audio by default and updates metadata")
    func finalizeDeletesRawAudio() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(
            rootURL: root.appendingPathComponent("Meetings"),
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let session = try MeetingNotesTestFixtures.session(phase: .completed)
        let chunkID = UUID()
        let chunk = MeetingAudioChunkMetadata(
            id: chunkID,
            trackID: MeetingNotesTestFixtures.trackID,
            sampleRange: try MeetingSampleRange(startFrame: 0, endFrame: 16_000, sampleRateHertz: 16_000),
            capturedAtMilliseconds: 1_001,
            byteCount: 3,
            encoding: .caf,
            storageState: .stored
        )
        let document = MeetingSessionDocument(
            session: session,
            tracks: [MeetingNotesTestFixtures.track()],
            audioChunks: [chunk]
        )
        let audioURL = try await store.writeRawAudio(
            Data([1, 2, 3]),
            sessionID: session.id,
            chunkID: chunkID,
            encoding: .caf
        )

        let finalized = try await store.finalize(document)

        #expect(finalized.audioChunks[0].storageState == .deleted)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(try permissions(at: root.appendingPathComponent("Meetings/index.json")) == 0o600)
    }

    @Test("malformed index is rebuilt from valid sidecars and truncated sidecars are isolated")
    func malformedArtifacts() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let store = MeetingSessionStore(rootURL: meetings, keyStore: InMemoryMeetingPersistenceKeyStore())
        let valid = try MeetingNotesTestFixtures.document()
        try await store.save(valid)
        try Data("{".utf8).write(to: meetings.appendingPathComponent("index.json"), options: .atomic)
        let truncatedID = UUID()
        let truncatedURL = meetings
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent("\(truncatedID.uuidString).json")
        try Data("{\"version\":1".utf8).write(to: truncatedURL, options: .atomic)

        let loaded = try await store.load()

        #expect(loaded.documents == [valid])
        #expect(loaded.issues.contains { $0.kind == .malformedIndex })
        #expect(loaded.issues.contains {
            $0.kind == .malformedSidecar && $0.artifactName == truncatedURL.lastPathComponent
        })
        let repairedData = try Data(contentsOf: meetings.appendingPathComponent("index.json"))
        #expect(repairedData.starts(with: Data("KAJIMTG2".utf8)))
    }

    @Test("an unreadable empty index is rebuilt after a development key migration")
    func unreadableEmptyIndexRecovery() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let originalKey = InMemoryMeetingPersistenceKeyStore()
        let originalStore = MeetingSessionStore(rootURL: meetings, keyStore: originalKey)
        _ = try await originalStore.load()
        let originalIndex = try Data(contentsOf: meetings.appendingPathComponent("index.json"))
        let migratedStore = MeetingSessionStore(
            rootURL: meetings,
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )

        let result = try await migratedStore.load()

        #expect(result.documents.isEmpty)
        #expect(result.issues.contains { $0.kind == .malformedIndex })
        let rebuiltIndex = try Data(contentsOf: meetings.appendingPathComponent("index.json"))
        #expect(rebuiltIndex != originalIndex)
        #expect(rebuiltIndex.starts(with: Data("KAJIMTG2".utf8)))
    }

    @Test("manual deletion removes malformed and partial UUID artifacts without decoding")
    func artifactBasedManualDeletion() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let store = MeetingSessionStore(rootURL: meetings, keyStore: InMemoryMeetingPersistenceKeyStore())
        _ = try await store.load()
        let malformedID = UUID()
        let malformedURL = meetings.appendingPathComponent("Sessions/\(malformedID.uuidString).json")
        try Data("{\"isPinned\":true".utf8).write(to: malformedURL)
        _ = try await store.writeRawAudio(
            Data([1]),
            sessionID: malformedID,
            chunkID: UUID(),
            encoding: .caf
        )
        let audioOnlyID = UUID()
        let audioOnlyURL = try await store.writeRawAudio(
            Data([2]),
            sessionID: audioOnlyID,
            chunkID: UUID(),
            encoding: .wav
        )

        #expect(try await store.deleteSession(id: malformedID))
        #expect(try await store.deleteSession(id: audioOnlyID))
        #expect(!FileManager.default.fileExists(atPath: malformedURL.path))
        #expect(!FileManager.default.fileExists(atPath: audioOnlyURL.path))
        #expect(try await store.load().documents.isEmpty)
        let indexData = try Data(contentsOf: meetings.appendingPathComponent("index.json"))
        #expect(indexData.starts(with: Data("KAJIMTG2".utf8)))
    }

    @Test("retention removes orphan audio and malformed or oversized UUID sidecars")
    func retentionCleansInvalidAndOrphanArtifacts() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let limits = MeetingPersistenceLimits(
            maximumIndexBytes: 16 * 1024,
            maximumSidecarBytes: 256,
            maximumAudioArtifactBytes: 1024
        )
        let store = MeetingSessionStore(
            rootURL: meetings,
            limits: limits,
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        _ = try await store.load()
        let malformedID = UUID()
        let oversizedID = UUID()
        let orphanID = UUID()
        let malformedURL = meetings.appendingPathComponent("Sessions/\(malformedID.uuidString).json")
        let oversizedURL = meetings.appendingPathComponent("Sessions/\(oversizedID.uuidString).json")
        try Data("{".utf8).write(to: malformedURL)
        try Data(repeating: 0x41, count: 257).write(to: oversizedURL)
        let malformedAudio = try await store.writeRawAudio(
            Data([1]),
            sessionID: malformedID,
            chunkID: UUID(),
            encoding: .caf
        )
        let orphanAudio = try await store.writeRawAudio(
            Data([2]),
            sessionID: orphanID,
            chunkID: UUID(),
            encoding: .caf
        )

        let result = try await store.enforceRetention(nowMilliseconds: 1)

        #expect(Set(result.deletedSessionIDs) == [malformedID, oversizedID, orphanID])
        #expect(!FileManager.default.fileExists(atPath: malformedURL.path))
        #expect(!FileManager.default.fileExists(atPath: oversizedURL.path))
        #expect(!FileManager.default.fileExists(atPath: malformedAudio.path))
        #expect(!FileManager.default.fileExists(atPath: orphanAudio.path))
        #expect(try await store.load().issues.isEmpty)
    }

    @Test("encoded sidecar limits reject writes before creating unreadable artifacts")
    func encodedWriteLimit() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let store = MeetingSessionStore(
            rootURL: meetings,
            limits: MeetingPersistenceLimits(
                maximumIndexBytes: 16 * 1024,
                maximumSidecarBytes: 128,
                maximumAudioArtifactBytes: 1024
            ),
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let document = try MeetingNotesTestFixtures.document()

        do {
            try await store.save(document)
            Issue.record("Expected the encoded sidecar limit to reject the write")
        } catch {
            #expect(error as? MeetingPersistenceError == .artifactTooLarge)
        }

        let sidecar = meetings.appendingPathComponent("Sessions/\(document.session.id.uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try await store.load().documents.isEmpty)
    }

    @Test("encoded index limits reject writes before committing a sidecar")
    func encodedIndexWriteLimit() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let store = MeetingSessionStore(
            rootURL: meetings,
            limits: MeetingPersistenceLimits(
                maximumIndexBytes: 64,
                maximumSidecarBytes: 16 * 1024,
                maximumAudioArtifactBytes: 1024
            ),
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let document = try MeetingNotesTestFixtures.document()

        do {
            try await store.save(document)
            Issue.record("Expected the encoded index limit to reject the write")
        } catch {
            #expect(error as? MeetingPersistenceError == .artifactTooLarge)
        }

        let sidecar = meetings.appendingPathComponent("Sessions/\(document.session.id.uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try await store.load().documents.isEmpty)
    }

    @Test("pending deletion tombstones retry cleanup and repair the index")
    func deletionTombstoneRecovery() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let store = MeetingSessionStore(rootURL: meetings, keyStore: InMemoryMeetingPersistenceKeyStore())
        let document = try MeetingNotesTestFixtures.document()
        try await store.save(document)
        let audio = try await store.writeRawAudio(
            Data([1]),
            sessionID: document.session.id,
            chunkID: UUID(),
            encoding: .caf
        )
        let tombstone = meetings
            .appendingPathComponent("DeletionTombstones", isDirectory: true)
            .appendingPathComponent("\(document.session.id.uuidString).tombstone")
        try Data(document.session.id.uuidString.utf8).write(to: tombstone)

        let loaded = try await store.load()

        #expect(loaded.documents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        #expect(!FileManager.default.fileExists(atPath: tombstone.path))
        let indexData = try Data(contentsOf: meetings.appendingPathComponent("index.json"))
        #expect(indexData.starts(with: Data("KAJIMTG2".utf8)))
    }

    @Test("finalization can enforce retention after durable final metadata")
    func finalizeAndEnforceRetention() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(
            rootURL: root.appendingPathComponent("Meetings"),
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let document = try MeetingNotesTestFixtures.document(phase: .completed)

        let result = try await store.finalizeAndEnforceRetention(
            document,
            nowMilliseconds: 31 * 86_400_000
        )

        #expect(result.document.session.id == document.session.id)
        #expect(result.retention.deletedSessionIDs == [document.session.id])
        #expect(try await store.load().documents.isEmpty)
    }

    @Test("valid plaintext sidecar migrates to an authenticated envelope")
    func plaintextMigration() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let sessions = meetings.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let document = try MeetingNotesTestFixtures.document()
        let sidecar = sessions.appendingPathComponent("\(document.session.id.uuidString).json")
        try JSONEncoder().encode(document).write(to: sidecar)
        let store = MeetingSessionStore(
            rootURL: meetings,
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )

        let loaded = try await store.load()

        #expect(loaded.documents == [document])
        #expect(try Data(contentsOf: sidecar).starts(with: Data("KAJIMTG2".utf8)))
        #expect(try permissions(at: sessions) == 0o700)
        #expect(try permissions(at: sidecar) == 0o600)
    }

    @Test("key loss fails generically without overwriting ciphertext")
    func keyLossIsNonDestructive() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let keyStore = InMemoryMeetingPersistenceKeyStore()
        let store = MeetingSessionStore(rootURL: meetings, keyStore: keyStore)
        let document = try MeetingNotesTestFixtures.document()
        try await store.save(document)
        let sidecar = meetings.appendingPathComponent("Sessions/\(document.session.id.uuidString).json")
        let index = meetings.appendingPathComponent("index.json")
        let originalSidecar = try Data(contentsOf: sidecar)
        let originalIndex = try Data(contentsOf: index)
        try keyStore.replaceKey()

        await #expect(throws: MeetingPersistenceError.artifactUnreadable) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: sidecar) == originalSidecar)
        #expect(try Data(contentsOf: index) == originalIndex)
    }

    @Test("sidecar ciphertext is bound to its session identifier")
    func authenticatedSessionBinding() async throws {
        let root = try MeetingNotesTestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings")
        let store = MeetingSessionStore(
            rootURL: meetings,
            keyStore: InMemoryMeetingPersistenceKeyStore()
        )
        let first = try MeetingNotesTestFixtures.document()
        let second = try MeetingNotesTestFixtures.document()
        try await store.save(first)
        try await store.save(second)
        let firstURL = meetings.appendingPathComponent("Sessions/\(first.session.id.uuidString).json")
        let secondURL = meetings.appendingPathComponent("Sessions/\(second.session.id.uuidString).json")
        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        try secondData.write(to: firstURL, options: .atomic)
        try firstData.write(to: secondURL, options: .atomic)

        await #expect(throws: MeetingPersistenceError.artifactUnreadable) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: firstURL) == secondData)
        #expect(try Data(contentsOf: secondURL) == firstData)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }
}
