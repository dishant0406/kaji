import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcription registry and reliability")
struct MeetingTranscriptionRegistryReliabilityTests {
    @Test("registry detects duplicates and validates routes")
    func registry() async throws {
        let provider = MeetingTranscriptionCoreTestProvider(
            descriptor: try MeetingTranscriptionCoreFixtures.descriptor()
        )
        let registry = try MeetingTranscriptionProviderRegistry(providers: [provider])
        #expect(await registry.descriptors().map(\.id) == ["test-provider"])
        try await registry.validate(MeetingTranscriptionCoreFixtures.route())
        await #expect(throws: MeetingTranscriptionProviderRegistryError.self) {
            try await registry.register(provider)
        }
    }

    @Test("retry policy bounds attempts, exponential delay and retry-after")
    func retryPolicy() throws {
        let policy = try MeetingTranscriptionRetryPolicy(
            maximumAttempts: 4,
            baseDelayMilliseconds: 100,
            maximumDelayMilliseconds: 1000,
            jitterBasisPoints: 1000,
            retryableClassifications: [.transient, .rateLimited]
        )
        #expect(policy.decision(classification: .transient, attempt: 1) == .retry(delayMilliseconds: 90 ... 110))
        #expect(policy.decision(
            classification: .rateLimited,
            attempt: 2,
            retryAfterMilliseconds: 800
        ) == .retry(delayMilliseconds: 720 ... 880))
        #expect(policy.decision(classification: .permanent, attempt: 1) == .stop)
        #expect(policy.decision(classification: .transient, attempt: 4) == .stop)
    }

    @Test("operation ledger identifies duplicate and conflicting operation identities")
    func operationLedger() async throws {
        let operationID = UUID()
        let first = MeetingTranscriptionOperationIdentity(
            packet: try MeetingTranscriptionCoreFixtures.packet(operationID: operationID)
        )
        let conflicting = MeetingTranscriptionOperationIdentity(
            packet: try MeetingTranscriptionCoreFixtures.packet(
                operationID: operationID,
                byte: 2
            )
        )
        let ledger = try MeetingTranscriptionOperationLedger(maximumEntries: 2)
        #expect(try await ledger.record(first) == .inserted)
        #expect(try await ledger.record(first) == .duplicate(.pending))
        await #expect(throws: MeetingTranscriptionOperationLedgerError.self) {
            try await ledger.record(conflicting)
        }
        try await ledger.transition(operationID: operationID, to: .acknowledged)
        try await ledger.transition(operationID: operationID, to: .completed)
        #expect(await ledger.entry(operationID: operationID)?.state == .completed)
    }

    @Test("epoch cutover accepts only the correct side of the boundary")
    func epochCutover() async throws {
        let oldEpoch = try MeetingTranscriptionCoreFixtures.epoch()
        let newEpoch = try MeetingTranscriptionCoreFixtures.epoch(1)
        let cutover = try MeetingProviderEpochCutover(
            trackID: MeetingTranscriptionCoreFixtures.trackID,
            previousEpoch: oldEpoch,
            nextEpoch: newEpoch,
            cutoverFrame: 16_000
        )
        let beforeCutover = try MeetingTranscriptionCoreFixtures.sampleRange(startFrame: 0, endFrame: 16_000)
        let crossingCutover = try MeetingTranscriptionCoreFixtures.sampleRange(startFrame: 15_000, endFrame: 17_000)
        let afterCutover = try MeetingTranscriptionCoreFixtures.sampleRange(startFrame: 16_000, endFrame: 32_000)
        #expect(cutover.accepts(
            epoch: oldEpoch,
            sampleRange: beforeCutover
        ))
        #expect(!cutover.accepts(
            epoch: oldEpoch,
            sampleRange: crossingCutover
        ))
        let coordinator = MeetingProviderEpochCoordinator()
        try await coordinator.activate(oldEpoch, trackID: MeetingTranscriptionCoreFixtures.trackID)
        try await coordinator.cutover(cutover)
        #expect(await coordinator.accepts(
            trackID: MeetingTranscriptionCoreFixtures.trackID,
            epoch: newEpoch,
            sampleRange: afterCutover
        ))
    }
}
