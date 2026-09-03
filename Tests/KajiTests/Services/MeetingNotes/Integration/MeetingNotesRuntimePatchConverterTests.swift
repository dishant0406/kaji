import Foundation
import Testing

@testable import Kaji

@Suite("Meeting notes runtime patch conversion")
struct MeetingNotesRuntimePatchConverterTests {
    @Test("strict conversion preserves evidence and allowed projects")
    func patchConversion() throws {
        let baseSegment = try MeetingNotesTestFixtures.segment()
        let segment = MeetingTranscriptSegment(
            id: baseSegment.id,
            trackID: baseSegment.trackID,
            sampleRange: baseSegment.sampleRange,
            startMilliseconds: baseSegment.startMilliseconds,
            endMilliseconds: baseSegment.endMilliseconds,
            text: baseSegment.text,
            speakerLabel: "Taylor",
            isFinal: baseSegment.isFinal,
            createdAtMilliseconds: baseSegment.createdAtMilliseconds
        )
        let value = KajiAgentJSONValue.object([
            "baseRevision": .number(0),
            "coveredStartMilliseconds": .number(Double(segment.startMilliseconds)),
            "coveredEndMilliseconds": .number(Double(segment.endMilliseconds)),
            "operations": .array([
                .object([
                    "op": .string("upsert_decision"),
                    "evidenceIds": .array([.string(segment.id.uuidString)]),
                    "decision": .object([
                        "id": .string(UUID().uuidString),
                        "text": .string("Ship Friday"),
                        "evidence": .array([
                            .object([
                                "transcriptSegmentId": .string(segment.id.uuidString),
                                "exactQuote": .string("desktop release on Friday"),
                            ]),
                        ]),
                    ]),
                ]),
                .object([
                    "op": .string("set_linked_projects"),
                    "evidenceIds": .array([.string(segment.id.uuidString)]),
                    "projectIds": .array([.string(MeetingNotesTestFixtures.projectID.uuidString)]),
                ]),
            ]),
        ])

        let patch = try MeetingNotesRuntimePatchConverter().convert(
            value,
            sessionID: UUID(),
            expectedBaseRevision: 0,
            transcriptSegments: [segment],
            allowedProjectIDs: [MeetingNotesTestFixtures.projectID]
        )

        #expect(patch.operations.count == 2)
        guard case let .upsertDecision(decision) = patch.operations[0] else {
            Issue.record("Expected decision operation")
            return
        }
        #expect(decision.evidence[0].transcriptSegmentID == segment.id)
    }

    @Test("unknown operation fields are rejected")
    func unknownFields() throws {
        let segment = try MeetingNotesTestFixtures.segment()
        let value = KajiAgentJSONValue.object([
            "baseRevision": .number(0),
            "coveredStartMilliseconds": .number(1),
            "coveredEndMilliseconds": .number(2),
            "operations": .array([
                .object([
                    "op": .string("set_title"),
                    "title": .string("Title"),
                    "evidenceIds": .array([.string(segment.id.uuidString)]),
                    "unexpected": .bool(true),
                ]),
            ]),
        ])

        #expect(throws: MeetingNotesRuntimePatchError.invalidPatch) {
            try MeetingNotesRuntimePatchConverter().convert(
                value,
                sessionID: UUID(),
                expectedBaseRevision: 0,
                transcriptSegments: [segment],
                allowedProjectIDs: []
            )
        }
    }

}
