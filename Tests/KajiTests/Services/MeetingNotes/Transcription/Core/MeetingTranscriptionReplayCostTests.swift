import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcription replay and cost")
struct MeetingTranscriptionReplayCostTests {
    @Test("PCM replay ring evicts whole old packets and looks up overlap")
    func replayRing() async throws {
        let ring = try MeetingPCMReplayRing(durationSeconds: 1)
        let first = try MeetingTranscriptionCoreFixtures.packet(startFrame: 0, endFrame: 8000)
        let second = try MeetingTranscriptionCoreFixtures.packet(startFrame: 8000, endFrame: 16_000)
        let third = try MeetingTranscriptionCoreFixtures.packet(startFrame: 16_000, endFrame: 24_000)
        try await ring.append(first)
        try await ring.append(second)
        try await ring.append(third)

        #expect(await ring.retainedFrameRange() == 8000 ..< 24_000)
        let evictedLookup = try await ring.replayPackets(
            overlapping: MeetingTranscriptionCoreFixtures.sampleRange(startFrame: 0, endFrame: 8000)
        )
        #expect(evictedLookup.isEmpty)
        let retainedLookup = try await ring.replayPackets(
            overlapping: MeetingTranscriptionCoreFixtures.sampleRange(startFrame: 15_000, endFrame: 17_000)
        )
        #expect(retainedLookup.map(\.operationID) == [second.operationID, third.operationID])
        #expect(retainedLookup.map(\.isReplay) == [true, true])
    }

    @Test("cost budget reserves atomically and preserves failed settlement")
    func costBudget() async throws {
        let budget = MeetingTranscriptionCostBudget(
            limit: try MeetingTranscriptionCost(currencyCode: "USD", micros: 100)
        )
        let first = UUID()
        let second = UUID()
        try await budget.reserve(
            operationID: first,
            estimatedCost: MeetingTranscriptionCost(currencyCode: "USD", micros: 70)
        )
        await #expect(throws: MeetingTranscriptionCostBudgetError.self) {
            try await budget.reserve(
                operationID: second,
                estimatedCost: MeetingTranscriptionCost(currencyCode: "USD", micros: 40)
            )
        }
        await #expect(throws: MeetingTranscriptionCostBudgetError.self) {
            try await budget.settle(
                operationID: first,
                actualCost: MeetingTranscriptionCost(currencyCode: "USD", micros: 101)
            )
        }
        #expect(await budget.snapshot().reservedMicros == 70)
        try await budget.settle(
            operationID: first,
            actualCost: MeetingTranscriptionCost(currencyCode: "USD", micros: 60)
        )
        try await budget.reserve(
            operationID: second,
            estimatedCost: MeetingTranscriptionCost(currencyCode: "USD", micros: 40)
        )
        let snapshot = await budget.snapshot()
        #expect(snapshot.settledMicros == 60)
        #expect(snapshot.reservedMicros == 40)
        #expect(snapshot.remainingMicros == 0)
    }
}
