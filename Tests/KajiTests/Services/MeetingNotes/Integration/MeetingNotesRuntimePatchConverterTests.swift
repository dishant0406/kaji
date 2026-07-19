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

    @MainActor
    @Test("meeting request stays in frame data and flattens only on the runtime wire")
    func frameEncoding() throws {
        let segment = try MeetingNotesTestFixtures.segment()
        let request = MeetingNotesSynthesisRequest(
            sessionID: UUID(),
            transcriptRevision: 1,
            transcriptSegments: [segment],
            currentNotes: .empty(sessionID: UUID(), title: "Meeting", createdAtMilliseconds: 1),
            projectContext: nil,
            sourceKindsByTrackID: [segment.trackID: .microphone],
            sourceLabelsByTrackID: [segment.trackID: "Microphone"],
            providerID: "provider",
            modelID: "model",
            allowedProjectIDs: []
        )
        let matchingRequest = MeetingNotesSynthesisRequest(
            sessionID: request.currentNotes.sessionID,
            transcriptRevision: 1,
            transcriptSegments: [segment],
            currentNotes: request.currentNotes,
            projectContext: nil,
            sourceKindsByTrackID: [segment.trackID: .microphone],
            sourceLabelsByTrackID: [segment.trackID: "Microphone"],
            providerID: "provider",
            modelID: "model",
            allowedProjectIDs: []
        )
        let frame = try KajiMeetingNotesAgentClient(launchResolver: { .missingRuntime }).makeFrame(matchingRequest)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any]

        #expect(frame.data?.objectValue?["newTranscriptSegments"] != nil)
        let transcript = frame.data?.objectValue?["newTranscriptSegments"]?.arrayValue?.first?.objectValue
        #expect(transcript?["speakerLabel"]?.stringValue == segment.speakerLabel)
        #expect(transcript?["sourceLabel"]?.stringValue == "Microphone")
        #expect(encoded?["newTranscriptSegments"] != nil)
        #expect(encoded?["data"] == nil)
    }
    @MainActor
    @Test("Swift request fields match the shared runtime fixture")
    func sharedRequestFixture() throws {
        let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("KajiAgentRuntime/test/fixtures/meeting-notes-swift-request.json")
        let fixture = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let segment = try MeetingNotesTestFixtures.segment()
        let notes = MeetingNotesSnapshot.empty(sessionID: UUID(), title: "Meeting", createdAtMilliseconds: 1)
        let request = MeetingNotesSynthesisRequest(
            sessionID: notes.sessionID,
            transcriptRevision: 1,
            transcriptSegments: [segment],
            currentNotes: notes,
            projectContext: nil,
            sourceKindsByTrackID: [segment.trackID: .microphone],
            sourceLabelsByTrackID: [segment.trackID: "Microphone"],
            providerID: "provider",
            modelID: "model",
            styleInstructions: "Use concise sentences.",
            allowedProjectIDs: []
        )
        let frame = try KajiMeetingNotesAgentClient(launchResolver: { .missingRuntime }).makeFrame(request)
        let payloadKeys = Set(try #require(frame.data?.objectValue).keys)
        let fixtureKeys = Set(fixture.keys)
        let transcriptKeys = Set(try #require(
            frame.data?.objectValue?["newTranscriptSegments"]?.arrayValue?.first?.objectValue
        ).keys)
        let fixtureTranscript = try #require(fixture["newTranscriptSegments"] as? [[String: Any]]).first

        #expect(payloadKeys == fixtureKeys)
        #expect(transcriptKeys == Set(try #require(fixtureTranscript).keys))
    }

    @MainActor
    @Test("runtime failure code maps to a typed Swift synthesis error")
    func typedRuntimeFailure() async throws {
        let segment = try MeetingNotesTestFixtures.segment()
        let notes = MeetingNotesSnapshot.empty(sessionID: UUID(), title: "Meeting", createdAtMilliseconds: 1)
        let request = MeetingNotesSynthesisRequest(
            sessionID: notes.sessionID,
            transcriptRevision: 1,
            transcriptSegments: [segment],
            currentNotes: notes,
            projectContext: nil
        )
        let response = KajiMeetingNotesResponseBox(
            process: KajiAgentProcess(),
            commandID: "typed-error",
            request: request
        )

        do {
            _ = try await response.run {
                response.handle(KajiAgentRPCFrame(
                    id: "typed-error",
                    type: "response",
                    success: false,
                    data: .object(["code": .string("credential_unavailable")])
                ))
            }
            Issue.record("Expected typed runtime failure")
        } catch let error as KajiMeetingNotesAgentError {
            #expect(error == .credentialUnavailable)
        }
    }

    @Test("model readiness request flattens validated selectors on the runtime wire")
    func modelReadinessFrameEncoding() throws {
        let frame = KajiAgentRPCFrame(
            id: "readiness",
            type: "validate_meeting_notes_model",
            data: .object([
                "provider": .string("opencode-go"),
                "modelId": .string("deepseek-v4-flash"),
            ])
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any]
        )

        #expect(object["provider"] as? String == "opencode-go")
        #expect(object["modelId"] as? String == "deepseek-v4-flash")
        #expect(object["data"] == nil)
    }

    @MainActor
    @Test("model readiness response decodes success without inference")
    func modelReadinessResponse() async {
        let response = KajiMeetingNotesModelReadinessResponseBox(
            process: KajiAgentProcess(),
            commandID: "readiness"
        )

        let readiness = await response.run {
            response.handle(KajiAgentRPCFrame(
                id: "readiness",
                type: "response",
                success: true,
                data: .object(["ready": .bool(true)])
            ))
        }

        #expect(readiness == .ready)
    }
}
