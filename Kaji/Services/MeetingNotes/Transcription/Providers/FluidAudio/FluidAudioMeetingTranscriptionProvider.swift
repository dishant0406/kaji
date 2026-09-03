import Foundation

enum FluidAudioMeetingTranscriptionError: Error, Equatable {
    case invalidRoute
    case modelNotCached
    case invalidPacket
    case invalidState
}

protocol FluidAudioMeetingTranscribing: Actor {
    func prepare(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws
    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String
}

extension SpeechTranscriber: FluidAudioMeetingTranscribing {}

final class FluidAudioMeetingTranscriptionProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    static let providerID = "fluid-audio"
    static let localRegionID = "local"

    let descriptor: MeetingTranscriptionProviderDescriptor

    private let modelsByID: [String: SpeechInputModel]
    private let isModelCached: @Sendable (SpeechInputModel) -> Bool
    private let makeTranscriber: @Sendable () -> any FluidAudioMeetingTranscribing
    private let nowMilliseconds: @Sendable () -> Int64

    init(
        models: [SpeechInputModel],
        isModelCached: @escaping @Sendable (SpeechInputModel) -> Bool = { $0.cacheState.isReady },
        makeTranscriber: @escaping @Sendable () -> any FluidAudioMeetingTranscribing = { SpeechTranscriber() },
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            max(0, Int64(Date().timeIntervalSince1970 * 1000))
        }
    ) throws {
        guard !models.isEmpty, Set(models.map(\.id)).count == models.count else {
            throw FluidAudioMeetingTranscriptionError.invalidRoute
        }
        descriptor = try Self.makeDescriptor(models: models)
        modelsByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        self.isModelCached = isModelCached
        self.makeTranscriber = makeTranscriber
        self.nowMilliseconds = nowMilliseconds
    }

    func route(modelID: String) throws -> MeetingTranscriptionRoute {
        guard modelsByID[modelID] != nil else { throw FluidAudioMeetingTranscriptionError.invalidRoute }
        return try MeetingTranscriptionRoute(
            providerID: Self.providerID,
            modelID: modelID,
            languageCodes: [],
            regionID: Self.localRegionID,
            mode: .localChunked,
            diarizationEnabled: false,
            retention: .none
        )
    }

    func readiness(for route: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        guard (try? route.validate(against: descriptor)) != nil,
              let model = modelsByID[route.modelID]
        else {
            return .unavailable
        }
        guard isModelCached(model) else {
            return .requiresDownload
        }
        return .ready
    }

    func makeSession(
        route: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        try route.validate(against: descriptor)
        guard let model = modelsByID[route.modelID] else {
            throw FluidAudioMeetingTranscriptionError.invalidRoute
        }
        return try FluidAudioMeetingTrackTranscriptionSession(
            model: model,
            context: MeetingTrackTranscriptionContextSnapshot(
                sessionID: context.sessionID,
                trackID: context.trackID,
                source: context.source,
                canonicalSampleRateHertz: context.canonicalSampleRateHertz,
                channelCount: context.channelCount,
                startedAtMilliseconds: context.startedAtMilliseconds,
                keyterms: context.keyterms
            ),
            transcriber: makeTranscriber(),
            isModelCached: isModelCached,
            nowMilliseconds: nowMilliseconds
        )
    }

    private static func makeDescriptor(models: [SpeechInputModel]) throws -> MeetingTranscriptionProviderDescriptor {
        let capabilities = try MeetingTranscriptionCapabilities(
            modes: [.localChunked],
            inputFormats: [
                MeetingTranscriptionInputFormat(
                    encoding: .pcmFloat32LittleEndian,
                    sampleRatesHertz: [MeetingAudioFormat.sampleRateHertz],
                    channelCounts: [MeetingAudioFormat.channelCount]
                ),
            ],
            timing: .supported,
            confidence: .unsupported,
            partialResults: .unsupported,
            diarization: .unsupported,
            languageIdentification: .unsupported,
            keyterms: .unsupported,
            sessionDuration: MeetingTranscriptionSessionDurationSupport(
                support: .supported,
                maximumSeconds: 604_800
            )
        )
        let privacy = try MeetingTranscriptionPrivacyDescriptor(
            processing: .localDevice,
            supportedRetention: [.none]
        )
        let region = try MeetingTranscriptionRegionDescriptor(
            id: localRegionID,
            displayName: "On This Mac"
        )
        let descriptors = try models.map { model in
            try MeetingTranscriptionModelDescriptor(
                id: model.id,
                displayName: model.title,
                capabilities: capabilities,
                supportedLanguageCodes: [],
                regions: [region],
                privacy: privacy,
                metadata: ["engine": model.engine.rawValue]
            )
        }
        return try MeetingTranscriptionProviderDescriptor(
            id: providerID,
            displayName: "FluidAudio",
            models: descriptors
        )
    }
}

private actor FluidAudioMeetingTrackTranscriptionSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case started
        case finished
        case cancelled
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let model: SpeechInputModel
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let transcriber: any FluidAudioMeetingTranscribing
    private let isModelCached: @Sendable (SpeechInputModel) -> Bool
    private let nowMilliseconds: @Sendable () -> Int64
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private var state = State.idle
    private var sequenceNumber: Int64 = 0

    init(
        model: SpeechInputModel,
        context: MeetingTrackTranscriptionContextSnapshot,
        transcriber: any FluidAudioMeetingTranscribing,
        isModelCached: @escaping @Sendable (SpeechInputModel) -> Bool,
        nowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.model = model
        self.context = context
        self.transcriber = transcriber
        self.isModelCached = isModelCached
        self.nowMilliseconds = nowMilliseconds
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
    }

    func start() async throws {
        guard state == .idle else { throw FluidAudioMeetingTranscriptionError.invalidState }
        state = .started
        emitSession(.starting)
        do {
            guard isModelCached(model) else { throw FluidAudioMeetingTranscriptionError.modelNotCached }
            try Task.checkCancellation()
            try await transcriber.prepare(model: model, progress: nil)
            try Task.checkCancellation()
            guard state == .started else { throw CancellationError() }
            emitSession(.ready)
        } catch {
            emitFailure(operationID: nil, classification: error is CancellationError ? .cancelled : .unavailable)
            state = error is CancellationError ? .cancelled : .finished
            eventChannel.finish()
            throw error
        }
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .started else { throw FluidAudioMeetingTranscriptionError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        guard packet.sessionID == context.sessionID,
              packet.trackID == context.trackID,
              packet.source == context.source,
              packet.sampleRateHertz == context.canonicalSampleRateHertz,
              packet.channelCount == context.channelCount,
              packet.encoding == .pcmFloat32LittleEndian
        else {
            throw FluidAudioMeetingTranscriptionError.invalidPacket
        }
        let samples = try Self.samples(from: packet)
        do {
            try Task.checkCancellation()
            let text = try await transcriber.transcribe(
                chunks: [SpeechAudioChunk(samples: samples, sampleRate: Double(packet.sampleRateHertz))],
                model: model
            )
            try Task.checkCancellation()
            guard state == .started else { throw CancellationError() }
            let emittedAt = nowMilliseconds()
            let eventContext = try makeEventContext(
                eventID: packet.operationID,
                operationID: packet.operationID,
                providerEpoch: packet.providerEpoch,
                emittedAtMilliseconds: emittedAt
            )
            let utterance = try MeetingTranscriptionUtterance(
                id: packet.operationID,
                revision: 0,
                sampleRange: packet.sampleRange,
                text: text,
                createdAtMilliseconds: max(context.startedAtMilliseconds, emittedAt)
            )
            eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            emitFailure(operationID: packet.operationID, providerEpoch: packet.providerEpoch, classification: .permanent)
            throw error
        }
    }

    func finish() async throws {
        guard state == .started else {
            if state == .finished || state == .cancelled {
                return
            }
            throw FluidAudioMeetingTranscriptionError.invalidState
        }
        emitSession(.draining)
        state = .finished
        emitSession(.completed)
        eventChannel.finish()
    }

    func cancel() async {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
        emitSession(.cancelled)
        eventChannel.finish()
    }

    private func emitSession(_ sessionState: MeetingTranscriptionSessionState) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: .initial,
            emittedAtMilliseconds: nowMilliseconds()
        ), let event = try? MeetingTranscriptionSessionEvent(
            context: eventContext,
            state: sessionState
        )
        else { return }
        eventChannel.send(.session(event))
    }

    private func emitFailure(
        operationID: UUID?,
        providerEpoch: MeetingProviderEpoch = .initial,
        classification: MeetingTranscriptionFailureClassification
    ) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: operationID,
            providerEpoch: providerEpoch,
            emittedAtMilliseconds: nowMilliseconds()
        ), let event = try? MeetingTranscriptionFailureEvent(
            context: eventContext,
            code: "local-transcription-failed",
            message: "Local transcription could not process the audio.",
            classification: classification
        )
        else { return }
        eventChannel.send(.failure(event))
    }

    private func makeEventContext(
        eventID: UUID,
        operationID: UUID?,
        providerEpoch: MeetingProviderEpoch,
        emittedAtMilliseconds: Int64
    ) throws -> MeetingTranscriptionEventContext {
        defer { sequenceNumber += 1 }
        return try MeetingTranscriptionEventContext(
            eventID: eventID,
            operationID: operationID,
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            providerEpoch: providerEpoch,
            sequenceNumber: sequenceNumber,
            emittedAtMilliseconds: max(0, emittedAtMilliseconds)
        )
    }

    private static func samples(from packet: MeetingNormalizedAudioPacket) throws -> [Float] {
        guard packet.bytes.count == packet.sampleRange.frameCount * 4 else {
            throw FluidAudioMeetingTranscriptionError.invalidPacket
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(packet.sampleRange.frameCount))
        packet.bytes.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let bits = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                samples.append(Float(bitPattern: bits))
            }
        }
        guard samples.allSatisfy(\.isFinite) else {
            throw FluidAudioMeetingTranscriptionError.invalidPacket
        }
        return samples
    }
}
