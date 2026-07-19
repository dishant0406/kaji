import Foundation
import Testing

@testable import Kaji

@Suite("Meeting notes reducer")
struct MeetingNotesReducerTests {
    @Test("valid patch applies with verified evidence and allowed project")
    func validPatch() throws {
        let sessionID = UUID()
        let segment = try MeetingNotesTestFixtures.segment()
        let snapshot = MeetingNotesSnapshot.empty(
            sessionID: sessionID,
            title: "Planning",
            createdAtMilliseconds: 1_000
        )
        let decisionID = UUID()
        let patch = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [
                .setSummary("Friday is the target."),
                .setLinkedProjects([MeetingNotesTestFixtures.projectID]),
                .upsertDecision(MeetingDecision(
                    id: decisionID,
                    text: "Ship Friday",
                    evidence: [MeetingEvidence(
                        transcriptSegmentID: segment.id,
                        exactQuote: "release on Friday"
                    )],
                    isPinned: false
                )),
            ]
        )

        let result = try MeetingNotesReducer().applying(
            patch,
            to: snapshot,
            transcriptSegments: [segment],
            allowedProjectIDs: [MeetingNotesTestFixtures.projectID],
            atMilliseconds: 2_100
        )

        #expect(result.revision == 1)
        #expect(result.decisions.map(\.id) == [decisionID])
        #expect(result.linkedProjectIDs == [MeetingNotesTestFixtures.projectID])
    }

    @Test("stale revision, fabricated evidence, unknown project, and long text are rejected")
    func strictRejections() throws {
        let sessionID = UUID()
        let segment = try MeetingNotesTestFixtures.segment()
        let snapshot = MeetingNotesSnapshot.empty(
            sessionID: sessionID,
            title: "Planning",
            createdAtMilliseconds: 1_000
        )
        let reducer = MeetingNotesReducer()
        let stale = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 1,
            operations: [.setSummary("Summary")]
        )
        #expect(throws: MeetingNotesReducerError.staleBaseRevision) {
            _ = try reducer.applying(
                stale,
                to: snapshot,
                transcriptSegments: [segment],
                allowedProjectIDs: [],
                atMilliseconds: 2_100
            )
        }
        let fabricated = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.upsertDecision(MeetingDecision(
                id: UUID(),
                text: "Unsupported",
                evidence: [MeetingEvidence(
                    transcriptSegmentID: segment.id,
                    exactQuote: "This was never said"
                )],
                isPinned: false
            ))]
        )
        #expect(throws: MeetingNotesReducerError.invalidEvidence) {
            _ = try reducer.applying(
                fabricated,
                to: snapshot,
                transcriptSegments: [segment],
                allowedProjectIDs: [],
                atMilliseconds: 2_100
            )
        }
        let unknownProject = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.setLinkedProjects([UUID()])]
        )
        #expect(throws: MeetingNotesReducerError.projectNotAllowed) {
            _ = try reducer.applying(
                unknownProject,
                to: snapshot,
                transcriptSegments: [segment],
                allowedProjectIDs: [MeetingNotesTestFixtures.projectID],
                atMilliseconds: 2_100
            )
        }
        let longText = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.setTitle(String(repeating: "x", count: 201))]
        )
        #expect(throws: MeetingNotesReducerError.invalidText) {
            _ = try reducer.applying(
                longText,
                to: snapshot,
                transcriptSegments: [segment],
                allowedProjectIDs: [],
                atMilliseconds: 2_100
            )
        }
    }

    @Test("pinned note items cannot be removed or silently unpinned")
    func pinProtection() throws {
        let sessionID = UUID()
        let decisionID = UUID()
        var snapshot = MeetingNotesSnapshot.empty(
            sessionID: sessionID,
            title: "Planning",
            createdAtMilliseconds: 1_000
        )
        snapshot.decisions = [MeetingDecision(
            id: decisionID,
            text: "Keep this",
            evidence: [],
            isPinned: true
        )]
        let remove = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.removeDecision(decisionID)]
        )
        #expect(throws: MeetingNotesReducerError.pinnedItemProtected) {
            _ = try MeetingNotesReducer().applying(
                remove,
                to: snapshot,
                transcriptSegments: [],
                allowedProjectIDs: [],
                atMilliseconds: 1_001
            )
        }
        let unpin = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.upsertDecision(MeetingDecision(
                id: decisionID,
                text: "Keep this",
                evidence: [],
                isPinned: false
            ))]
        )
        #expect(throws: MeetingNotesReducerError.pinMutationNotAllowed) {
            _ = try MeetingNotesReducer().applying(
                unpin,
                to: snapshot,
                transcriptSegments: [],
                allowedProjectIDs: [],
                atMilliseconds: 1_001
            )
        }
    }

    @Test("operation and category count limits are enforced")
    func countLimits() throws {
        let sessionID = UUID()
        let snapshot = MeetingNotesSnapshot.empty(
            sessionID: sessionID,
            title: "Planning",
            createdAtMilliseconds: 1_000
        )
        var limits = MeetingNotesReducerLimits()
        limits.maximumOperations = 1
        let operationLimitedReducer = MeetingNotesReducer(limits: limits)
        let twoOperations = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.setTitle("One"), .setSummary("Two")]
        )
        #expect(throws: MeetingNotesReducerError.tooManyOperations) {
            _ = try operationLimitedReducer.applying(
                twoOperations,
                to: snapshot,
                transcriptSegments: [],
                allowedProjectIDs: [],
                atMilliseconds: 1_001
            )
        }
        limits.maximumOperations = 100
        limits.maximumItemsPerCategory = 0
        let itemLimitedReducer = MeetingNotesReducer(limits: limits)
        let itemPatch = MeetingNotesPatch(
            sessionID: sessionID,
            baseRevision: 0,
            operations: [.upsertOpenQuestion(MeetingOpenQuestion(
                id: UUID(),
                text: "Who owns this?",
                isResolved: false,
                evidence: [],
                isPinned: false
            ))]
        )
        #expect(throws: MeetingNotesReducerError.itemLimitExceeded) {
            _ = try itemLimitedReducer.applying(
                itemPatch,
                to: snapshot,
                transcriptSegments: [],
                allowedProjectIDs: [],
                atMilliseconds: 1_001
            )
        }
    }
}
