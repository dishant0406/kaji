import Foundation
import Testing

@testable import Kaji

enum MeetingTranscriptionCoreFixtures {
    static let sessionID = UUID()
    static let trackID = UUID()

    static func epoch(_ value: Int = 0) throws -> MeetingProviderEpoch {
        try #require(MeetingProviderEpoch(rawValue: value))
    }

    static func sampleRange(
        startFrame: Int64 = 0,
        endFrame: Int64 = 16_000,
        sampleRateHertz: Int = 16_000
    ) throws -> MeetingCanonicalSampleRange {
        try MeetingCanonicalSampleRange(
            startFrame: startFrame,
            endFrame: endFrame,
            sampleRateHertz: sampleRateHertz
        )
    }

    static func packet(
        operationID: UUID = UUID(),
        startFrame: Int64 = 0,
        endFrame: Int64 = 160,
        sampleRateHertz: Int = 16_000,
        epoch: Int = 0,
        byte: UInt8 = 1
    ) throws -> MeetingNormalizedAudioPacket {
        let frameCount = Int(endFrame - startFrame)
        return try MeetingNormalizedAudioPacket(
            operationID: operationID,
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            sampleRange: sampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: sampleRateHertz
            ),
            encoding: .pcmSigned16LittleEndian,
            sampleRateHertz: sampleRateHertz,
            channelCount: 1,
            bytes: Data(repeating: byte, count: frameCount * 2),
            providerEpoch: self.epoch(epoch)
        )
    }

    static func capabilities(diarization: MeetingTranscriptionCapabilitySupport = .supported) throws
        -> MeetingTranscriptionCapabilities
    {
        try MeetingTranscriptionCapabilities(
            modes: [.localChunked, .cloudBatch, .cloudRealtime],
            inputFormats: [MeetingTranscriptionInputFormat(
                encoding: .pcmSigned16LittleEndian,
                sampleRatesHertz: [16_000],
                channelCounts: [1]
            )],
            timing: .supported,
            confidence: .supported,
            partialResults: .supported,
            diarization: diarization,
            languageIdentification: .supported,
            keyterms: .supported,
            sessionDuration: MeetingTranscriptionSessionDurationSupport(
                support: .supported,
                maximumSeconds: 3600
            )
        )
    }

    static func descriptor(
        providerID: String = "test-provider",
        modelID: String = "test-model",
        diarization: MeetingTranscriptionCapabilitySupport = .supported
    ) throws -> MeetingTranscriptionProviderDescriptor {
        try MeetingTranscriptionProviderDescriptor(
            id: providerID,
            displayName: "Test Provider",
            models: [MeetingTranscriptionModelDescriptor(
                id: modelID,
                displayName: "Test Model",
                capabilities: capabilities(diarization: diarization),
                supportedLanguageCodes: ["en-US", "fr"],
                regions: [MeetingTranscriptionRegionDescriptor(id: "local", displayName: "Local")],
                privacy: MeetingTranscriptionPrivacyDescriptor(
                    processing: .localDevice,
                    supportedRetention: [.none, .transient]
                )
            )]
        )
    }

    static func route(
        providerID: String = "test-provider",
        modelID: String = "test-model",
        diarizationEnabled: Bool = true,
        fallbacks: [MeetingTranscriptionFallback] = []
    ) throws -> MeetingTranscriptionRoute {
        try MeetingTranscriptionRoute(
            providerID: providerID,
            modelID: modelID,
            languageCodes: ["en-US"],
            regionID: "local",
            mode: .localChunked,
            diarizationEnabled: diarizationEnabled,
            retention: .none,
            fallbacks: fallbacks
        )
    }

    static func context(
        eventID: UUID = UUID(),
        sequenceNumber: Int64,
        epoch: Int = 0
    ) throws -> MeetingTranscriptionEventContext {
        try MeetingTranscriptionEventContext(
            eventID: eventID,
            operationID: UUID(),
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            providerEpoch: self.epoch(epoch),
            sequenceNumber: sequenceNumber,
            emittedAtMilliseconds: 1_000 + sequenceNumber
        )
    }

    static func utterance(
        id: UUID = UUID(),
        revision: Int,
        text: String,
        startFrame: Int64 = 0,
        endFrame: Int64 = 16_000
    ) throws -> MeetingTranscriptionUtterance {
        try MeetingTranscriptionUtterance(
            id: id,
            revision: revision,
            sampleRange: sampleRange(startFrame: startFrame, endFrame: endFrame),
            text: text,
            confidence: 0.9,
            words: [MeetingNormalizedWord(
                id: UUID(),
                text: text,
                sampleRange: sampleRange(startFrame: startFrame, endFrame: endFrame),
                confidence: 0.8,
                speakerID: "speaker-1",
                languageCode: "en-US"
            )],
            speaker: MeetingNormalizedSpeaker(id: "speaker-1", label: "Speaker 1", confidence: 0.95),
            language: MeetingNormalizedLanguage(code: "en-US", confidence: 0.99),
            createdAtMilliseconds: 2_000 + Int64(revision)
        )
    }
}

actor MeetingTranscriptionCoreTestSession: MeetingTrackTranscriptionSession {
    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    init() {
        events = AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func start() async throws {}
    func submit(_: MeetingNormalizedAudioPacket) async throws {}
    func finish() async throws {}
    func cancel() async {}
}

struct MeetingTranscriptionCoreTestProvider: MeetingTranscriptionProvider {
    let descriptor: MeetingTranscriptionProviderDescriptor

    func readiness(for _: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        .ready
    }

    func makeSession(
        route _: MeetingTranscriptionRoute,
        context _: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        MeetingTranscriptionCoreTestSession()
    }
}
