import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcription provider event channel")
struct MeetingTranscriptionProviderEventChannelTests {
    @Test("stalled consumers retain critical events while coalescing revisions")
    func revisionPressure() async throws {
        let channel = MeetingTranscriptionProviderEventChannel(capacity: 2)
        let operationID = UUID()
        channel.send(.partial(try partial(operationID: operationID, revision: 0)))
        channel.send(.replacement(try replacement(operationID: operationID, revision: 1)))
        for revision in 2 ... 1000 {
            channel.send(.replacement(try replacement(operationID: operationID, revision: revision)))
        }
        channel.send(.final(try final(operationID: operationID, revision: 1001)))
        channel.finish()

        var events: [MeetingTranscriptionProviderEvent] = []
        for try await event in channel.events { events.append(event) }
        let latest = try #require(events.compactMap(utterance).first)

        #expect(events.count == 2)
        #expect(latest.revision == 1000)
        #expect(events.contains { if case .final = $0 { true } else { false } })
    }

    @Test("critical-only overflow terminates with an explicit retryable bounded error")
    func criticalOverflow() async throws {
        let channel = MeetingTranscriptionProviderEventChannel(capacity: 2)
        channel.send(.final(try final(operationID: UUID(), revision: 0)))
        channel.send(.final(try final(operationID: UUID(), revision: 0)))
        channel.send(.final(try final(operationID: UUID(), revision: 0)))
        var iterator = channel.events.makeAsyncIterator()

        _ = try await iterator.next()
        _ = try await iterator.next()
        do {
            _ = try await iterator.next()
            Issue.record("Expected bounded overflow")
        } catch let error as MeetingTranscriptionProviderEventChannelError {
            #expect(error == .capacityExceeded)
            #expect(error.isRetryable)
        }
    }

    private func partial(operationID: UUID, revision: Int) throws -> MeetingTranscriptionPartialEvent {
        MeetingTranscriptionPartialEvent(
            context: try context(operationID: operationID, sequence: revision),
            utterance: try transcript(operationID: operationID, revision: revision)
        )
    }

    private func replacement(operationID: UUID, revision: Int) throws -> MeetingTranscriptionReplacementEvent {
        try MeetingTranscriptionReplacementEvent(
            context: context(operationID: operationID, sequence: revision),
            replacesUtteranceID: operationID,
            replacesRevision: revision - 1,
            utterance: transcript(operationID: operationID, revision: revision)
        )
    }

    private func final(operationID: UUID, revision: Int) throws -> MeetingTranscriptionFinalEvent {
        MeetingTranscriptionFinalEvent(
            context: try context(operationID: operationID, sequence: revision),
            utterance: try transcript(operationID: operationID, revision: revision)
        )
    }

    private func transcript(operationID: UUID, revision: Int) throws -> MeetingTranscriptionUtterance {
        try MeetingTranscriptionUtterance(
            id: operationID,
            revision: revision,
            sampleRange: MeetingCanonicalSampleRange(startFrame: 0, endFrame: 800, sampleRateHertz: 16_000),
            text: "revision-\(revision)",
            createdAtMilliseconds: 1
        )
    }

    private func context(operationID: UUID, sequence: Int) throws -> MeetingTranscriptionEventContext {
        try MeetingTranscriptionEventContext(
            eventID: UUID(),
            operationID: operationID,
            sessionID: MeetingTranscriptionCoreFixtures.sessionID,
            trackID: MeetingTranscriptionCoreFixtures.trackID,
            source: .microphone,
            providerEpoch: .initial,
            sequenceNumber: Int64(sequence),
            emittedAtMilliseconds: 1
        )
    }

    private func utterance(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionUtterance? {
        switch event {
        case let .partial(value): value.utterance
        case let .replacement(value): value.utterance
        default: nil
        }
    }
}
