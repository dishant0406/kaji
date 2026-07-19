import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcript revision reducer")
struct MeetingTranscriptRevisionReducerTests {
    @Test("duplicate and out-of-order revisions do not replace current text")
    func orderingAndDuplicates() throws {
        let utteranceID = UUID()
        let eventID = UUID()
        var reducer = try MeetingTranscriptRevisionReducer()
        let current = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(eventID: eventID, sequenceNumber: 2),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 2,
                text: "current"
            )
        ))
        #expect(try reducer.apply(current) == .applied)
        #expect(try reducer.apply(current) == .duplicate)
        let old = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 1),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 1,
                text: "old"
            )
        ))
        #expect(try reducer.apply(old) == .outOfOrder)
        #expect(reducer.ledger.record(id: utteranceID)?.current.text == "current")
    }

    @Test("replacement updates partial while preserving stable segment ID and metadata")
    func partialReplacement() throws {
        let utteranceID = UUID()
        var reducer = try MeetingTranscriptRevisionReducer()
        let initial = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 0),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 0,
                text: "initial"
            )
        ))
        let replacement = MeetingTranscriptionProviderEvent.replacement(
            try MeetingTranscriptionReplacementEvent(
                context: MeetingTranscriptionCoreFixtures.context(sequenceNumber: 1),
                replacesUtteranceID: utteranceID,
                replacesRevision: 0,
                utterance: MeetingTranscriptionCoreFixtures.utterance(
                    id: utteranceID,
                    revision: 1,
                    text: "replacement"
                )
            )
        )
        #expect(try reducer.apply(initial) == .applied)
        #expect(try reducer.apply(replacement) == .applied)
        let record = try #require(reducer.ledger.record(id: utteranceID))
        #expect(record.revisions.count == 2)
        #expect(record.current.words.count == 1)
        #expect(record.current.speaker?.label == "Speaker 1")
        #expect(record.current.language?.code == "en-US")
        let segment = try #require(reducer.materializedSegments().first)
        #expect(segment.id == utteranceID)
        #expect(segment.text == "replacement")
        #expect(segment.speakerLabel == "Speaker 1")
    }

    @Test("committed final is immutable")
    func finalImmutability() throws {
        let utteranceID = UUID()
        var reducer = try MeetingTranscriptRevisionReducer()
        let partial = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 0),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 0,
                text: "draft"
            )
        ))
        let final = MeetingTranscriptionProviderEvent.final(MeetingTranscriptionFinalEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 1),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 1,
                text: "committed"
            )
        ))
        let laterFinal = MeetingTranscriptionProviderEvent.final(MeetingTranscriptionFinalEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 2),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 2,
                text: "mutated"
            )
        ))
        #expect(try reducer.apply(partial) == .applied)
        #expect(try reducer.apply(final) == .applied)
        #expect(try reducer.apply(laterFinal) == .finalImmutable)
        let segment = try #require(reducer.materializedSegments().first)
        #expect(segment.text == "committed")
        #expect(segment.isFinal)
    }

    @Test("new epoch removes stale partials, preserves finals and rejects old epoch events")
    func staleEpochs() throws {
        let finalID = UUID()
        let stalePartialID = UUID()
        let newPartialID = UUID()
        var reducer = try MeetingTranscriptRevisionReducer()
        let oldFinal = MeetingTranscriptionProviderEvent.final(MeetingTranscriptionFinalEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 0),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: finalID,
                revision: 0,
                text: "old final",
                startFrame: 0,
                endFrame: 8000
            )
        ))
        let oldPartial = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 1),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: stalePartialID,
                revision: 0,
                text: "old partial",
                startFrame: 8000,
                endFrame: 16_000
            )
        ))
        let newPartial = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 2, epoch: 1),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: newPartialID,
                revision: 0,
                text: "new partial",
                startFrame: 8000,
                endFrame: 16_000
            )
        ))
        let lateOld = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 3),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: UUID(),
                revision: 0,
                text: "late old"
            )
        ))
        #expect(try reducer.apply(oldFinal) == .applied)
        #expect(try reducer.apply(oldPartial) == .applied)
        #expect(try reducer.apply(newPartial) == .applied)
        #expect(reducer.ledger.record(id: finalID) != nil)
        #expect(reducer.ledger.record(id: stalePartialID) == nil)
        #expect(try reducer.apply(lateOld) == .staleEpoch)
        #expect(reducer.ledger.record(id: newPartialID)?.current.source == .microphone)
    }

    @Test("ledger round trip preserves utterance and revision identities")
    func stableIDs() throws {
        let utteranceID = UUID()
        var reducer = try MeetingTranscriptRevisionReducer()
        let event = MeetingTranscriptionProviderEvent.final(MeetingTranscriptionFinalEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 0),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 0,
                text: "stable"
            )
        ))
        #expect(try reducer.apply(event) == .applied)
        let decoded = try JSONDecoder().decode(
            MeetingTranscriptRevisionLedger.self,
            from: JSONEncoder().encode(reducer.ledger)
        )
        #expect(decoded == reducer.ledger)
        #expect(decoded.record(id: utteranceID)?.id == utteranceID)
    }

    @Test("processed event IDs prune to a bounded deduplication window")
    func eventIDPruning() throws {
        var reducer = try MeetingTranscriptRevisionReducer(
            maximumUtterances: 10,
            maximumProcessedEvents: 2
        )
        let eventIDs = [UUID(), UUID(), UUID()]
        for (index, eventID) in eventIDs.enumerated() {
            let event = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
                context: try MeetingTranscriptionCoreFixtures.context(
                    eventID: eventID,
                    sequenceNumber: Int64(index)
                ),
                utterance: try MeetingTranscriptionCoreFixtures.utterance(
                    id: UUID(),
                    revision: 0,
                    text: "event \(index)"
                )
            ))
            #expect(try reducer.apply(event) == .applied)
        }

        #expect(reducer.ledger.processedEventIDs == Set(eventIDs.suffix(2)))
        #expect(reducer.ledger.processedEventOrder == Array(eventIDs.suffix(2)))
    }

    @Test("aggregate revision bytes reject oversized ledger growth")
    func aggregateRevisionByteLimit() throws {
        var reducer = try MeetingTranscriptRevisionReducer(
            maximumUtterances: 10,
            maximumProcessedEvents: 10,
            maximumRevisionBytes: 1024
        )
        let event = MeetingTranscriptionProviderEvent.partial(MeetingTranscriptionPartialEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 0),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: UUID(),
                revision: 0,
                text: String(repeating: "a", count: 1000)
            )
        ))

        #expect(throws: MeetingTranscriptionValidationError.invalidEvent("revisionByteCapacity")) {
            _ = try reducer.apply(event)
        }
        #expect(reducer.ledger.records.isEmpty)
    }

    @Test("single utterance lookup materializes without scanning the ledger")
    func directUtteranceLookup() throws {
        let utteranceID = UUID()
        var reducer = try MeetingTranscriptRevisionReducer()
        let event = MeetingTranscriptionProviderEvent.final(MeetingTranscriptionFinalEvent(
            context: try MeetingTranscriptionCoreFixtures.context(sequenceNumber: 0),
            utterance: try MeetingTranscriptionCoreFixtures.utterance(
                id: utteranceID,
                revision: 0,
                text: "direct"
            )
        ))
        _ = try reducer.apply(event)

        #expect(try reducer.materializedSegment(id: utteranceID)?.text == "direct")
        #expect(try reducer.materializedSegment(id: UUID()) == nil)
    }
}
