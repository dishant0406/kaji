import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcript canonicalization")
struct MeetingTranscriptCanonicalizerTests {
    @Test("overlapping token suffix and prefix are emitted once")
    func trimsOverlap() throws {
        let earlier = try segment(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            startFrame: 0,
            endFrame: 100,
            text: "we should ship Friday"
        )
        let later = try segment(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            startFrame: 80,
            endFrame: 180,
            text: "ship Friday and notify sales"
        )

        let canonical = MeetingTranscriptCanonicalizer.trimmingDuplicatePrefix(
            from: later,
            after: earlier
        )

        #expect(canonical.text == "and notify sales")
        #expect(canonical.id == later.id)
        #expect(canonical.trackID == later.trackID)
        #expect(canonical.sampleRange == later.sampleRange)
        #expect(canonical.startMilliseconds == later.startMilliseconds)
        #expect(canonical.endMilliseconds == later.endMilliseconds)
        #expect(canonical.createdAtMilliseconds == later.createdAtMilliseconds)
    }

    @Test("alignment normalizes case and punctuation")
    func normalizesTokens() throws {
        let earlier = try segment(startFrame: 0, endFrame: 100, text: "Decision: SHIP Friday!")
        let later = try segment(startFrame: 75, endFrame: 175, text: "ship, friday - and notify sales")

        let canonical = MeetingTranscriptCanonicalizer.trimmingDuplicatePrefix(
            from: later,
            after: earlier
        )

        #expect(canonical.text == "and notify sales")
    }

    @Test("non-overlapping evidence remains unchanged")
    func preservesNonOverlap() throws {
        let earlier = try segment(startFrame: 0, endFrame: 100, text: "ship Friday")
        let later = try segment(startFrame: 100, endFrame: 200, text: "ship Friday and notify sales")

        #expect(MeetingTranscriptCanonicalizer.trimmingDuplicatePrefix(
            from: later,
            after: earlier
        ) == later)
    }

    private func segment(
        id: UUID = UUID(),
        startFrame: Int64,
        endFrame: Int64,
        text: String
    ) throws -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(
            id: id,
            trackID: MeetingAudioTestFixtures.sourceID,
            sampleRange: try MeetingSampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: MeetingAudioFormat.sampleRateHertz
            ),
            startMilliseconds: 1_000 + startFrame,
            endMilliseconds: 1_000 + endFrame,
            text: text,
            speakerLabel: "Speaker",
            isFinal: true,
            createdAtMilliseconds: 2_000
        )
    }
}
