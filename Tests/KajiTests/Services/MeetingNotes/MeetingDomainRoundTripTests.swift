import Foundation
import Testing

@testable import Kaji

@Suite("Meeting domain round trips")
struct MeetingDomainRoundTripTests {
    @Test("session document round-trips stable IDs and integer timing")
    func documentRoundTrip() throws {
        var session = try MeetingNotesTestFixtures.session(phase: .completed)
        session.title = "Release decision"
        let segment = try MeetingNotesTestFixtures.segment()
        var notes = MeetingNotesSnapshot.empty(
            sessionID: session.id,
            title: session.title,
            createdAtMilliseconds: 1_000
        )
        notes.revision = 1
        notes.summary = "The release date was agreed."
        notes.linkedProjectIDs = [MeetingNotesTestFixtures.projectID]
        notes.decisions = [MeetingDecision(
            id: UUID(),
            text: "Release on Friday",
            evidence: [MeetingEvidence(
                transcriptSegmentID: segment.id,
                exactQuote: "desktop release on Friday"
            )],
            isPinned: true
        )]
        notes.updatedAtMilliseconds = 2_002
        let document = MeetingSessionDocument(
            session: session,
            tracks: [MeetingNotesTestFixtures.track()],
            transcriptSegments: [segment],
            notes: notes,
            noteRevisions: [MeetingNotesRevision(
                id: UUID(),
                patchID: UUID(),
                baseRevision: 0,
                resultingRevision: 1,
                createdAtMilliseconds: 2_002,
                source: .synthesis
            )]
        )

        try MeetingDocumentValidator().validate(document)
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(MeetingSessionDocument.self, from: data)

        #expect(decoded == document)
        #expect(decoded.transcriptSegments[0].sampleRange.startFrame == 0)
        #expect(decoded.transcriptSegments[0].startMilliseconds == 1_001)
    }

    @Test("settings enforce interval and privacy defaults during decoding")
    func settingsValidation() throws {
        #expect(MeetingNotesSettings.privacyDefaults.synthesisIntervalMinutes == 5)
        #expect(!MeetingNotesSettings.privacyDefaults.retainRawAudio)
        #expect(!MeetingNotesSettings.privacyDefaults.includeSystemAudio)
        #expect(!MeetingNotesSettings.privacyDefaults.shareProjectContext)
        #expect(throws: MeetingNotesSettingsError.invalidSynthesisInterval) {
            _ = try MeetingNotesSettings(synthesisIntervalMinutes: 31)
        }
        let malformed = Data("""
        {"synthesisIntervalMinutes":0,"retainRawAudio":false,"retentionDays":30,"includeSystemAudio":false,"shareProjectContext":false}
        """.utf8)
        #expect(throws: MeetingNotesSettingsError.invalidSynthesisInterval) {
            _ = try JSONDecoder().decode(MeetingNotesSettings.self, from: malformed)
        }
    }

    @Test("notes patches round-trip associated operations")
    func patchRoundTrip() throws {
        let patch = MeetingNotesPatch(
            sessionID: UUID(),
            baseRevision: 7,
            operations: [
                .setTitle("Updated title"),
                .setLinkedProjects([MeetingNotesTestFixtures.projectID]),
                .upsertRisk(MeetingRisk(
                    id: UUID(),
                    text: "Release could slip",
                    mitigation: "Keep scope fixed",
                    severity: .high,
                    evidence: [],
                    isPinned: false
                )),
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(MeetingNotesPatch.self, from: data)

        #expect(decoded == patch)
    }

    @Test("lifecycle rejects non-monotonic and terminal transitions")
    func lifecycleValidation() throws {
        var session = try MeetingNotesTestFixtures.session()
        try session.transition(to: .recording, atMilliseconds: 1_001)
        try session.transition(to: .completed, atMilliseconds: 1_002)
        #expect(throws: MeetingDomainError.invalidLifecycleTransition) {
            try session.transition(to: .recording, atMilliseconds: 1_003)
        }
    }
}
