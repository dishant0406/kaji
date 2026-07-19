import Foundation
import Testing

@testable import Kaji

@Suite("FluidAudio meeting transcription provider")
struct FluidAudioMeetingTranscriptionProviderTests {
    @Test("descriptor and readiness reflect the configured local model")
    func descriptorAndReadiness() async throws {
        let model = MeetingAudioTestFixtures.model
        let unavailableProvider = try FluidAudioMeetingTranscriptionProvider(
            models: [model],
            isModelCached: { _ in false }
        )
        let unavailableRoute = try unavailableProvider.route(modelID: model.id)

        #expect(unavailableProvider.descriptor.models.map(\.id) == [model.id])
        #expect(unavailableProvider.descriptor.models.first?.displayName == model.title)
        #expect(unavailableProvider.descriptor.models.first?.metadata["engine"] == model.engine.rawValue)
        #expect(await unavailableProvider.readiness(for: unavailableRoute).state == .requiresDownload)

        let readyProvider = try FluidAudioMeetingTranscriptionProvider(
            models: [model],
            isModelCached: { _ in true }
        )
        let readyRoute = try readyProvider.route(modelID: model.id)
        #expect(await readyProvider.readiness(for: readyRoute).state == .ready)
    }

    @Test("local final events preserve packet identity samples and canonical range across retry")
    func stableRetryIdentity() async throws {
        let runtime = FluidAudioTranscriberRecorder(responses: ["normalized text", "normalized text"])
        let model = MeetingAudioTestFixtures.model
        let provider = try FluidAudioMeetingTranscriptionProvider(
            models: [model],
            isModelCached: { _ in true },
            makeTranscriber: { runtime },
            nowMilliseconds: { 20_000 }
        )
        let route = try provider.route(modelID: model.id)
        let operationID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let sessionID = UUID()
        let chunk = try MeetingAudioTestFixtures.chunk(
            operationID: operationID,
            startFrame: 320,
            samples: [0.25, -0.5]
        )
        let packet = try chunk.normalizedPacket(sessionID: sessionID)
        let session = try await provider.makeSession(
            route: route,
            context: chunk.transcriptionContext(sessionID: sessionID)
        )
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.submit(packet)
        try await session.submit(packet)
        try await session.finish()
        let finalEvents = try await collector.value.compactMap { event -> MeetingTranscriptionFinalEvent? in
            guard case let .final(final) = event else { return nil }
            return final
        }

        #expect(finalEvents.count == 2)
        #expect(finalEvents.map(\.context.eventID) == [operationID, operationID])
        #expect(finalEvents.map(\.context.operationID) == [operationID, operationID])
        #expect(finalEvents.map(\.utterance.id) == [operationID, operationID])
        #expect(finalEvents.map(\.utterance.text) == ["normalized text", "normalized text"])
        #expect(finalEvents.map(\.utterance.sampleRange) == [packet.sampleRange, packet.sampleRange])
        #expect(await runtime.samples() == [[0.25, -0.5], [0.25, -0.5]])
    }
}

private actor FluidAudioTranscriberRecorder: FluidAudioMeetingTranscribing {
    private var responses: [String]
    private var receivedSamples: [[Float]] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func prepare(model _: SpeechInputModel, progress _: SpeechTranscriber.ProgressHandler?) async throws {}

    func transcribe(chunks: [SpeechAudioChunk], model _: SpeechInputModel) async throws -> String {
        receivedSamples.append(chunks.flatMap(\.samples))
        guard !responses.isEmpty else { throw SpeechInputError.emptyTranscript }
        return responses.removeFirst()
    }

    func samples() -> [[Float]] {
        receivedSamples
    }
}
