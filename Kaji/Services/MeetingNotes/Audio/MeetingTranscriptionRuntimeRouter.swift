import Foundation

enum MeetingTranscriptionRuntimeRouterError: Error, Equatable {
    case invalidCapacity
    case invalidPacket
    case queueFull(UUID)
    case finished
}

enum MeetingTranscriptionRuntimeEvent {
    case partial(MeetingTranscriptSegment)
    case final(MeetingTranscriptSegment)
    case committedMetadata(MeetingCommittedTranscriptMetadata)
    case metadataAmendment(MeetingCommittedTranscriptMetadata)
    case usage(MeetingTranscriptionUsageEvent)
    case rateLimit(MeetingTranscriptionRateLimitEvent)
    case warning(MeetingTranscriptionWarningEvent)
    case session(MeetingTranscriptionSessionEvent)
    case health(MeetingTranscriptionTrackHealthEvent)
    case failure(MeetingTranscriptionFailureEvent)
    case failureRange(MeetingTranscriptionFailureEvent, MeetingCanonicalSampleRange)
}

struct MeetingTranscriptionRuntimeFallback {
    let provider: any MeetingTranscriptionProvider
    let route: MeetingTranscriptionRoute
}

actor MeetingTranscriptionRuntimeRouter {
    typealias EventHandler = @Sendable (MeetingTranscriptionRuntimeEvent) async -> Void
    typealias Sleep = @Sendable (Int64) async throws -> Void
    typealias RetryDelay = @Sendable (ClosedRange<Int64>) -> Int64

    private enum Lifecycle {
        case running
        case finishing
        case finished
        case cancelled
    }

    private struct TrackState {
        let context: MeetingTrackTranscriptionContextSnapshot
        let continuation: AsyncStream<MeetingNormalizedAudioPacket>.Continuation
        let worker: Task<Void, Never>
        let replayRing: MeetingPCMReplayRing
        var epoch: MeetingProviderEpoch
        var generation: UUID
        var committedPrefix: CommittedPrefix
    }

    private struct FailedTrack {
        let context: MeetingTrackTranscriptionContextSnapshot
        let failure: MeetingTranscriptionFailureEvent
    }

    private enum EpochOutcome {
        case completed
        case cancelled
        case rotate
        case failure(MeetingTranscriptionFailureEvent, MeetingCanonicalSampleRange?)
    }

    private struct EpochInput {
        let replayPackets: [MeetingNormalizedAudioPacket]
        let context: MeetingTrackTranscriptionContextSnapshot
        let provider: any MeetingTranscriptionProvider
        let route: MeetingTranscriptionRoute
        let epoch: MeetingProviderEpoch
        let generation: UUID
        let useFallback: Bool
    }

    private enum EpochSignal {
        case inputFinished
        case eventStreamFinished(expected: Bool)
        case rotate
        case failure(MeetingTranscriptionFailureEvent, MeetingCanonicalSampleRange?)
    }

    private struct CommittedPrefix {
        private(set) var throughFrame: Int64
        private var ranges: [Range<Int64>] = []

        init(originFrame: Int64) {
            throughFrame = originFrame
        }

        mutating func insert(_ range: MeetingCanonicalSampleRange) {
            guard range.endFrame > throughFrame else { return }
            ranges.append(max(throughFrame, range.startFrame) ..< range.endFrame)
            ranges.sort { left, right in
                if left.lowerBound == right.lowerBound { return left.upperBound < right.upperBound }
                return left.lowerBound < right.lowerBound
            }
            var merged: [Range<Int64>] = []
            for range in ranges {
                guard let last = merged.last, range.lowerBound <= last.upperBound else {
                    merged.append(range)
                    continue
                }
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            }
            ranges = merged
            while let first = ranges.first, first.lowerBound <= throughFrame {
                throughFrame = max(throughFrame, first.upperBound)
                ranges.removeFirst()
            }
        }
    }

    private let provider: any MeetingTranscriptionProvider
    private let route: MeetingTranscriptionRoute
    private let fallback: MeetingTranscriptionRuntimeFallback?
    private let packetCapacity: Int
    private let retryPolicy: MeetingTranscriptionRetryPolicy
    private let sleep: Sleep
    private let replaySleep: Sleep
    private let retryDelay: RetryDelay
    private let eventHandler: EventHandler
    private var reducer: MeetingTranscriptRevisionReducer
    private var tracks: [UUID: TrackState] = [:]
    private var failedTracks: [UUID: FailedTrack] = [:]
    private var retiredWorkers: [Task<Void, Never>] = []
    private var cutoverFrames: [UUID: Int64] = [:]
    private var lifecycle = Lifecycle.running

    init(
        provider: any MeetingTranscriptionProvider,
        route: MeetingTranscriptionRoute,
        fallback: MeetingTranscriptionRuntimeFallback? = nil,
        packetCapacity: Int? = nil,
        retryPolicy: MeetingTranscriptionRetryPolicy? = nil,
        sleep: @escaping Sleep = { milliseconds in
            try await Task.sleep(for: .milliseconds(milliseconds))
        },
        replaySleep: @escaping Sleep = { milliseconds in
            try await Task.sleep(for: .milliseconds(milliseconds))
        },
        retryDelay: @escaping RetryDelay = { Int64.random(in: $0) },
        eventHandler: @escaping EventHandler
    ) throws {
        let resolvedCapacity = packetCapacity ?? Self.packetCapacity(for: route.mode)
        guard 1 ... 4096 ~= resolvedCapacity else {
            throw MeetingTranscriptionRuntimeRouterError.invalidCapacity
        }
        try route.validate(against: provider.descriptor)
        if let fallback {
            try fallback.route.validate(against: fallback.provider.descriptor)
            guard fallback.route.mode == .localChunked,
                  fallback.provider.descriptor.model(id: fallback.route.modelID)?.privacy.processing == .localDevice
            else {
                throw MeetingTranscriptionValidationError.invalidRoute("fallback")
            }
        }
        self.provider = provider
        self.route = route
        self.fallback = fallback
        self.packetCapacity = resolvedCapacity
        self.retryPolicy = try retryPolicy ?? MeetingTranscriptionRetryPolicy(
            maximumAttempts: 4,
            baseDelayMilliseconds: 250,
            maximumDelayMilliseconds: 10000,
            jitterBasisPoints: 2000,
            retryableClassifications: [.transient, .rateLimited, .unavailable]
        )
        self.sleep = sleep
        self.replaySleep = replaySleep
        self.retryDelay = retryDelay
        self.eventHandler = eventHandler
        reducer = try MeetingTranscriptRevisionReducer()
    }

    static func packetCapacity(for mode: MeetingTranscriptionMode) -> Int {
        switch mode {
        case .cloudRealtime:
            512
        case .cloudBatch:
            32
        case .localChunked:
            16
        }
    }

    func submit(
        _ packet: MeetingNormalizedAudioPacket,
        context: MeetingTrackTranscriptionContextSnapshot
    ) async throws {
        guard lifecycle == .running else { throw MeetingTranscriptionRuntimeRouterError.finished }
        guard packet.sessionID == context.sessionID,
              packet.trackID == context.trackID,
              packet.source == context.source,
              packet.sampleRateHertz == context.canonicalSampleRateHertz,
              packet.channelCount == context.channelCount
        else {
            throw MeetingTranscriptionRuntimeRouterError.invalidPacket
        }
        if let failed = failedTracks[context.trackID] {
            guard failed.context == context else { throw MeetingTranscriptionRuntimeRouterError.invalidPacket }
            await eventHandler(.failureRange(failed.failure, packet.sampleRange))
            return
        }
        let track = try await trackState(for: context, originFrame: packet.sampleRange.startFrame)
        try await track.replayRing.append(packet)
        switch track.continuation.yield(packet) {
        case .enqueued:
            return
        case .dropped:
            let failure = try queueFailure(packet: packet, epoch: track.epoch)
            await eventHandler(.failure(failure))
            await eventHandler(.failureRange(failure, packet.sampleRange))
        case .terminated:
            throw MeetingTranscriptionRuntimeRouterError.finished
        @unknown default:
            throw MeetingTranscriptionRuntimeRouterError.finished
        }
    }

    func finish() async {
        guard lifecycle == .running else { return }
        lifecycle = .finishing
        let activeTracks = Array(tracks.values)
        activeTracks.forEach { $0.continuation.finish() }
        for track in activeTracks {
            await track.worker.value
        }
        for worker in retiredWorkers {
            await worker.value
        }
        tracks.removeAll()
        retiredWorkers.removeAll()
        failedTracks.removeAll()
        lifecycle = .finished
    }

    func replayPackets(
        trackID: UUID,
        overlapping range: MeetingCanonicalSampleRange
    ) async throws -> [MeetingNormalizedAudioPacket] {
        guard let track = tracks[trackID] else { return [] }
        return try await track.replayRing.replayPackets(overlapping: range)
    }

    func cancel() async {
        guard lifecycle != .finished, lifecycle != .cancelled else { return }
        lifecycle = .cancelled
        let activeTracks = Array(tracks.values)
        for track in activeTracks {
            track.continuation.finish()
            track.worker.cancel()
        }
        for track in activeTracks {
            await track.worker.value
        }
        for worker in retiredWorkers {
            worker.cancel()
            await worker.value
        }
        tracks.removeAll()
        retiredWorkers.removeAll()
        failedTracks.removeAll()
    }

    private func trackState(
        for context: MeetingTrackTranscriptionContextSnapshot,
        originFrame: Int64
    ) async throws -> TrackState {
        if let existing = tracks[context.trackID] {
            guard existing.context == context else {
                throw MeetingTranscriptionRuntimeRouterError.invalidPacket
            }
            return existing
        }
        let stream = AsyncStream<MeetingNormalizedAudioPacket>.makeStream(
            bufferingPolicy: .bufferingOldest(packetCapacity)
        )
        let replayRing = try MeetingPCMReplayRing()
        let generation = UUID()
        let worker = Task { [weak self] in
            guard let self else { return }
            await self.runTrack(
                packets: stream.stream,
                context: context,
                replayRing: replayRing,
                initialGeneration: generation
            )
        }
        let state = TrackState(
            context: context,
            continuation: stream.continuation,
            worker: worker,
            replayRing: replayRing,
            epoch: .initial,
            generation: generation,
            committedPrefix: CommittedPrefix(originFrame: originFrame)
        )
        tracks[context.trackID] = state
        return state
    }

    private func runTrack(
        packets: AsyncStream<MeetingNormalizedAudioPacket>,
        context: MeetingTrackTranscriptionContextSnapshot,
        replayRing: MeetingPCMReplayRing,
        initialGeneration: UUID
    ) async {
        var epoch = MeetingProviderEpoch.initial
        var generation = initialGeneration
        var attempt = 1
        var useFallback = false
        var shouldReplay = false
        while !Task.isCancelled {
            let selectedProvider = useFallback ? fallback?.provider : provider
            let selectedRoute = useFallback ? fallback?.route : route
            guard let selectedProvider, let selectedRoute else { return }
            do {
                try activate(trackID: context.trackID, epoch: epoch, generation: generation)
                await emitHealth(
                    trackID: context.trackID,
                    epoch: epoch,
                    state: useFallback ? .localFallback : .starting,
                    code: useFallback ? "local-fallback" : nil
                )
                let session = try await selectedProvider.makeSession(route: selectedRoute, context: context)
                let replayPackets = shouldReplay ? try await replayRing.allReplayPackets() : []
                let outcome = await runEpoch(
                    session: session,
                    packets: packets,
                    input: EpochInput(
                        replayPackets: replayPackets,
                        context: context,
                        provider: selectedProvider,
                        route: selectedRoute,
                        epoch: epoch,
                        generation: generation,
                        useFallback: useFallback
                    )
                )
                switch outcome {
                case .completed:
                    await emitHealth(trackID: context.trackID, epoch: epoch, state: .completed)
                    return
                case .cancelled:
                    await emitHealth(trackID: context.trackID, epoch: epoch, state: .cancelled)
                    return
                case .rotate:
                    attempt = 1
                case let .failure(failure, range):
                    if let range {
                        await eventHandler(.failureRange(failure, range))
                    }
                    guard !useFallback else {
                        await exhaust(trackID: context.trackID, context: context, epoch: epoch, failure: failure)
                        return
                    }
                    let classification = retryClassification(failure.classification)
                    switch retryPolicy.decision(
                        classification: classification,
                        attempt: attempt,
                        retryAfterMilliseconds: failure.retryAfterMilliseconds
                    ) {
                    case let .retry(delayRange):
                        await emitHealth(
                            trackID: context.trackID,
                            epoch: epoch,
                            state: classification == .rateLimited ? .rateLimited : .reconnecting,
                            code: classification == .rateLimited ? "rate-limited" : "reconnecting"
                        )
                        try await sleep(retryDelay(delayRange))
                        attempt += 1
                    case .stop:
                        if fallback != nil {
                            useFallback = true
                            attempt = 1
                        } else {
                            await exhaust(trackID: context.trackID, context: context, epoch: epoch, failure: failure)
                            return
                        }
                    }
                }
                guard let nextEpoch = MeetingProviderEpoch(rawValue: epoch.rawValue + 1) else {
                    throw MeetingTranscriptionRuntimeRouterError.invalidPacket
                }
                epoch = nextEpoch
                generation = UUID()
                shouldReplay = true
            } catch is CancellationError {
                await emitHealth(trackID: context.trackID, epoch: epoch, state: .cancelled)
                return
            } catch {
                guard let failure = try? runtimeFailure(
                    context: context,
                    epoch: epoch,
                    code: "runtime-session-failed",
                    classification: .unavailable
                )
                else { return }
                if !useFallback, fallback != nil {
                    useFallback = true
                    guard let nextEpoch = MeetingProviderEpoch(rawValue: epoch.rawValue + 1) else { return }
                    epoch = nextEpoch
                    generation = UUID()
                    shouldReplay = true
                    continue
                }
                await eventHandler(.failure(failure))
                await exhaust(trackID: context.trackID, context: context, epoch: epoch, failure: failure)
                return
            }
        }
    }

    private func runEpoch(
        session: any MeetingTrackTranscriptionSession,
        packets: AsyncStream<MeetingNormalizedAudioPacket>,
        input: EpochInput
    ) async -> EpochOutcome {
        let replayPackets = input.replayPackets
        let context = input.context
        let provider = input.provider
        let route = input.route
        let epoch = input.epoch
        let generation = input.generation
        let useFallback = input.useFallback
        do {
            try await session.start()
            await emitHealth(trackID: context.trackID, epoch: epoch, state: useFallback ? .localFallback : .ready)
        } catch is CancellationError {
            await session.cancel()
            return .cancelled
        } catch {
            await session.cancel()
            guard let failure = try? runtimeFailure(
                context: context,
                epoch: epoch,
                code: "runtime-session-start-failed",
                classification: .unavailable
            )
            else { return .cancelled }
            return .failure(failure, nil)
        }
        let replayEndFrame = replayPackets.map(\.sampleRange.endFrame).max() ?? 0
        let shouldPace = route.mode == .cloudRealtime && !replayPackets.isEmpty
        let completion = EpochCompletion()
        let durationSeconds = route.mode == .cloudRealtime
            ? provider.descriptor.model(id: route.modelID)?.capabilities.sessionDuration.maximumSeconds
            : nil
        return await withTaskGroup(of: EpochSignal.self, returning: EpochOutcome.self) { group in
            group.addTask { [weak self] in
                guard let self else { return .eventStreamFinished(expected: true) }
                do {
                    for try await event in session.events {
                        let accepted = await self.consume(
                            event,
                            context: context,
                            route: route,
                            epoch: epoch,
                            generation: generation
                        )
                        guard accepted else { continue }
                        switch event {
                        case let .failure(failure):
                            return await .failure(failure, self.range(for: failure, trackID: context.trackID))
                        case let .warning(warning)
                            where warning.isRecoverable && warning.code.lowercased().contains("rotation"):
                            return .rotate
                        default:
                            continue
                        }
                    }
                    return await .eventStreamFinished(expected: completion.isFinishing)
                } catch is CancellationError {
                    return await .eventStreamFinished(expected: completion.isFinishing)
                } catch {
                    guard let failure = try? await self.runtimeFailure(
                        context: context,
                        epoch: epoch,
                        code: "runtime-event-stream-failed",
                        classification: .transient
                    )
                    else { return .eventStreamFinished(expected: true) }
                    return .failure(failure, nil)
                }
            }
            group.addTask { [weak self] in
                guard let self else { return .inputFinished }
                do {
                    for replay in replayPackets {
                        try Task.checkCancellation()
                        try await session.submit(self.packet(replay, epoch: epoch, useFallback: useFallback))
                        if shouldPace {
                            try await self.replaySleep(self.packetDurationMilliseconds(replay))
                        }
                    }
                    for await livePacket in packets {
                        try Task.checkCancellation()
                        if replayEndFrame > 0, livePacket.sampleRange.endFrame <= replayEndFrame { continue }
                        let submitted = try await self.packet(livePacket, epoch: epoch, useFallback: useFallback)
                        do {
                            try await session.submit(submitted)
                            if shouldPace {
                                try await self.replaySleep(self.packetDurationMilliseconds(livePacket))
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            let failure = try await self.runtimeFailure(
                                context: context,
                                epoch: epoch,
                                operationID: livePacket.operationID,
                                code: "runtime-submit-failed",
                                classification: .transient
                            )
                            return .failure(failure, livePacket.sampleRange)
                        }
                    }
                    try Task.checkCancellation()
                    await self.emitHealth(trackID: context.trackID, epoch: epoch, state: .draining)
                    await completion.beginFinishing()
                    try await session.finish()
                    return .inputFinished
                } catch is CancellationError {
                    return .inputFinished
                } catch {
                    guard let failure = try? await self.runtimeFailure(
                        context: context,
                        epoch: epoch,
                        code: "runtime-session-failed",
                        classification: .transient
                    )
                    else { return .inputFinished }
                    return .failure(failure, nil)
                }
            }
            if let durationSeconds {
                group.addTask { [weak self] in
                    guard let self else { return .eventStreamFinished(expected: true) }
                    do {
                        let leadSeconds = min(30, max(1, durationSeconds / 10))
                        try await self.sleep(Int64(max(1, durationSeconds - leadSeconds)) * 1000)
                        return .rotate
                    } catch {
                        return .eventStreamFinished(expected: true)
                    }
                }
            }
            var inputFinished = false
            var eventStreamFinished = false
            while let signal = await group.next() {
                switch signal {
                case .inputFinished:
                    inputFinished = true
                    guard eventStreamFinished else { continue }
                    group.cancelAll()
                    if Task.isCancelled {
                        await session.cancel()
                        return .cancelled
                    }
                    return .completed
                case let .eventStreamFinished(expected) where expected:
                    eventStreamFinished = true
                    guard inputFinished else { continue }
                    group.cancelAll()
                    if Task.isCancelled {
                        await session.cancel()
                        return .cancelled
                    }
                    return .completed
                case .eventStreamFinished:
                    group.cancelAll()
                    await session.cancel()
                    guard let failure = try? runtimeFailure(
                        context: context,
                        epoch: epoch,
                        code: "runtime-event-stream-ended",
                        classification: .transient
                    )
                    else { return .cancelled }
                    return .failure(failure, nil)
                case .rotate:
                    group.cancelAll()
                    await session.cancel()
                    return .rotate
                case let .failure(failure, range):
                    group.cancelAll()
                    await session.cancel()
                    return .failure(failure, range)
                }
            }
            await session.cancel()
            return Task.isCancelled ? .cancelled : .completed
        }
    }

    @discardableResult
    private func consume(
        _ event: MeetingTranscriptionProviderEvent,
        context: MeetingTrackTranscriptionContextSnapshot,
        route: MeetingTranscriptionRoute,
        epoch: MeetingProviderEpoch,
        generation: UUID
    ) async -> Bool {
        guard lifecycle == .running || lifecycle == .finishing,
              let track = tracks[context.trackID],
              track.generation == generation,
              track.epoch == epoch,
              event.context.sessionID == context.sessionID,
              event.context.trackID == context.trackID,
              event.context.source == context.source,
              event.context.providerEpoch == epoch
        else {
            return false
        }
        if let range = event.sampleRange,
           epoch.rawValue > 0,
           let cutoverFrame = cutoverFrames[context.trackID],
           range.endFrame <= cutoverFrame
        {
            return false
        }
        do {
            let result = try reducer.apply(event)
            switch event {
            case let .partial(partial) where result == .applied:
                if let segment = try materializedSegment(id: partial.utterance.id, context: context) {
                    await eventHandler(.partial(segment))
                }
            case let .final(final) where result == .applied:
                if let segment = try materializedSegment(id: final.utterance.id, context: context) {
                    await eventHandler(.final(segment))
                }
                if let metadata = committedMetadata(id: final.utterance.id, route: route) {
                    await eventHandler(.committedMetadata(metadata))
                }
                if var current = tracks[context.trackID], current.generation == generation {
                    current.committedPrefix.insert(final.utterance.sampleRange)
                    tracks[context.trackID] = current
                }
            case let .replacement(replacement) where result == .applied:
                if let segment = try materializedSegment(id: replacement.utterance.id, context: context) {
                    await eventHandler(.partial(segment))
                }
            case let .metadataAmendment(amendment) where result == .applied:
                if let metadata = committedMetadata(id: amendment.utteranceID, route: route) {
                    await eventHandler(.metadataAmendment(metadata))
                }
            case let .usage(usage):
                await eventHandler(.usage(usage))
            case let .rateLimit(rateLimit):
                await eventHandler(.rateLimit(rateLimit))
                await emitHealth(
                    trackID: context.trackID,
                    epoch: epoch,
                    state: .rateLimited,
                    code: "rate-limited",
                    updatedAtMilliseconds: rateLimit.context.emittedAtMilliseconds
                )
            case let .warning(warning):
                await eventHandler(.warning(warning))
            case let .session(session):
                await eventHandler(.session(session))
            case let .failure(failure):
                await eventHandler(.failure(failure))
            case .partial,
                 .final,
                 .replacement,
                 .metadataAmendment:
                return true
            }
            return true
        } catch {
            if let failure = try? runtimeFailure(
                context: context,
                epoch: epoch,
                code: "runtime-event-invalid",
                classification: .permanent
            ) {
                await eventHandler(.failure(failure))
            }
            return false
        }
    }

    private func committedMetadata(
        id: UUID,
        route: MeetingTranscriptionRoute
    ) -> MeetingCommittedTranscriptMetadata? {
        guard let revision = reducer.ledger.record(id: id)?.current, revision.isFinal else { return nil }
        return MeetingCommittedTranscriptMetadata(
            id: revision.id,
            operationID: revision.operationID,
            trackID: revision.trackID,
            source: revision.source,
            providerID: route.providerID,
            modelID: route.modelID,
            regionID: route.regionID,
            mode: route.mode,
            providerEpoch: revision.providerEpoch,
            confidence: revision.confidence,
            words: revision.words,
            speaker: revision.speaker,
            language: revision.language,
            committedAtMilliseconds: revision.createdAtMilliseconds
        )
    }

    private func materializedSegment(
        id: UUID,
        context: MeetingTrackTranscriptionContextSnapshot
    ) throws -> MeetingTranscriptSegment? {
        guard let segment = try reducer.materializedSegments(timelineOriginMilliseconds: 0).first(where: { $0.id == id })
        else { return nil }
        let start = context.startedAtMilliseconds.addingReportingOverflow(segment.startMilliseconds)
        let end = context.startedAtMilliseconds.addingReportingOverflow(segment.endMilliseconds)
        guard !start.overflow, !end.overflow else {
            throw MeetingTranscriptionRuntimeRouterError.invalidPacket
        }
        return MeetingTranscriptSegment(
            id: segment.id,
            trackID: segment.trackID,
            sampleRange: segment.sampleRange,
            startMilliseconds: start.partialValue,
            endMilliseconds: end.partialValue,
            text: segment.text,
            speakerLabel: segment.speakerLabel,
            isFinal: segment.isFinal,
            createdAtMilliseconds: segment.createdAtMilliseconds
        )
    }

    private func activate(trackID: UUID, epoch: MeetingProviderEpoch, generation: UUID) throws {
        guard var track = tracks[trackID] else { throw MeetingTranscriptionRuntimeRouterError.finished }
        if epoch > track.epoch {
            cutoverFrames[trackID] = track.committedPrefix.throughFrame
        }
        track.epoch = epoch
        track.generation = generation
        tracks[trackID] = track
    }

    private func exhaust(
        trackID: UUID,
        context: MeetingTrackTranscriptionContextSnapshot,
        epoch: MeetingProviderEpoch,
        failure: MeetingTranscriptionFailureEvent
    ) async {
        guard let track = tracks.removeValue(forKey: trackID) else { return }
        track.continuation.finish()
        retiredWorkers.append(track.worker)
        failedTracks[trackID] = FailedTrack(context: context, failure: failure)
        await emitHealth(trackID: trackID, epoch: epoch, state: .failed, code: failure.code)
        if let retained = await track.replayRing.retainedFrameRange(),
           let range = try? MeetingCanonicalSampleRange(
               startFrame: retained.lowerBound,
               endFrame: retained.upperBound,
               sampleRateHertz: context.canonicalSampleRateHertz
           )
        {
            await eventHandler(.failureRange(failure, range))
        }
    }

    private func range(
        for failure: MeetingTranscriptionFailureEvent,
        trackID: UUID
    ) async -> MeetingCanonicalSampleRange? {
        guard let operationID = failure.context.operationID,
              let ring = tracks[trackID]?.replayRing
        else { return nil }
        return await ring.packet(operationID: operationID)?.sampleRange
    }

    private func queueFailure(
        packet: MeetingNormalizedAudioPacket,
        epoch: MeetingProviderEpoch
    ) throws -> MeetingTranscriptionFailureEvent {
        try MeetingTranscriptionFailureEvent(
            context: eventContext(packet: packet, epoch: epoch),
            code: "runtime-queue-overflow",
            message: "Audio exceeded the transcription queue capacity.",
            classification: .unavailable
        )
    }

    private func runtimeFailure(
        context: MeetingTrackTranscriptionContextSnapshot,
        epoch: MeetingProviderEpoch,
        operationID: UUID? = nil,
        code: String,
        classification: MeetingTranscriptionFailureClassification
    ) throws -> MeetingTranscriptionFailureEvent {
        try MeetingTranscriptionFailureEvent(
            context: MeetingTranscriptionEventContext(
                eventID: UUID(),
                operationID: operationID,
                sessionID: context.sessionID,
                trackID: context.trackID,
                source: context.source,
                providerEpoch: epoch,
                sequenceNumber: 0,
                emittedAtMilliseconds: nowMilliseconds()
            ),
            code: code,
            message: "The transcription session could not process the audio.",
            classification: classification
        )
    }

    private func eventContext(
        packet: MeetingNormalizedAudioPacket,
        epoch: MeetingProviderEpoch
    ) throws -> MeetingTranscriptionEventContext {
        try MeetingTranscriptionEventContext(
            eventID: UUID(),
            operationID: packet.operationID,
            sessionID: packet.sessionID,
            trackID: packet.trackID,
            source: packet.source,
            providerEpoch: epoch,
            sequenceNumber: 0,
            emittedAtMilliseconds: nowMilliseconds()
        )
    }

    private func emitHealth(
        trackID: UUID,
        epoch: MeetingProviderEpoch,
        state: MeetingTranscriptionTrackRuntimeState,
        code: String? = nil,
        updatedAtMilliseconds: Int64? = nil
    ) async {
        guard let health = try? MeetingTranscriptionTrackHealthEvent(
            trackID: trackID,
            providerEpoch: epoch,
            state: state,
            updatedAtMilliseconds: updatedAtMilliseconds ?? nowMilliseconds(),
            code: code
        )
        else { return }
        await eventHandler(.health(health))
    }

    private func packet(
        _ packet: MeetingNormalizedAudioPacket,
        epoch: MeetingProviderEpoch,
        useFallback: Bool
    ) throws -> MeetingNormalizedAudioPacket {
        let replay = try packet.replaying(providerEpoch: epoch)
        guard useFallback else { return replay }
        return try replay.float32PCM()
    }

    private func packetDurationMilliseconds(_ packet: MeetingNormalizedAudioPacket) -> Int64 {
        let frames = packet.sampleRange.frameCount
        let sampleRate = Int64(packet.sampleRateHertz)
        let whole = frames / sampleRate
        let remainder = frames % sampleRate
        return max(1, whole * 1000 + (remainder * 1000 + sampleRate - 1) / sampleRate)
    }

    private func retryClassification(
        _ classification: MeetingTranscriptionFailureClassification
    ) -> MeetingTranscriptionRetryClassification {
        switch classification {
        case .transient: .transient
        case .rateLimited: .rateLimited
        case .authentication: .authentication
        case .authorization: .authorization
        case .invalidRequest: .invalidRequest
        case .unavailable: .unavailable
        case .quotaExceeded: .quotaExceeded
        case .cancelled: .cancelled
        case .permanent: .permanent
        }
    }

    private func nowMilliseconds() -> Int64 {
        max(0, Int64(Date().timeIntervalSince1970 * 1000))
    }
}

private actor EpochCompletion {
    private(set) var isFinishing = false

    func beginFinishing() {
        isFinishing = true
    }
}

private extension MeetingTranscriptionProviderEvent {
    var sampleRange: MeetingCanonicalSampleRange? {
        switch self {
        case let .partial(event): event.utterance.sampleRange
        case let .final(event): event.utterance.sampleRange
        case let .replacement(event): event.utterance.sampleRange
        case .metadataAmendment,
             .usage,
             .rateLimit,
             .warning,
             .session,
             .failure:
            nil
        }
    }
}

private extension MeetingNormalizedAudioPacket {
    func float32PCM() throws -> Self {
        guard encoding == .pcmSigned16LittleEndian else { return self }
        let values = bytes.withUnsafeBytes { rawBuffer -> [Float] in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return samples.map { sample in
                Float(Int16(littleEndian: sample)) / Float(Int16.max)
            }
        }
        let encoded = values.map(\.bitPattern.littleEndian).withUnsafeBytes { Data($0) }
        return try Self(
            operationID: operationID,
            sessionID: sessionID,
            trackID: trackID,
            source: source,
            sampleRange: sampleRange,
            encoding: .pcmFloat32LittleEndian,
            sampleRateHertz: sampleRateHertz,
            channelCount: channelCount,
            bytes: encoded,
            providerEpoch: providerEpoch,
            isReplay: isReplay,
            isEndOfStream: isEndOfStream
        )
    }
}

extension MeetingTranscriptionAudioChunk {
    func normalizedPacket(
        sessionID: UUID,
        mode: MeetingTranscriptionMode = .localChunked,
        providerEpoch: MeetingProviderEpoch = .initial
    ) throws -> MeetingNormalizedAudioPacket {
        guard samples.count == sampleRange.frameCount,
              sampleRateHertz == sampleRange.sampleRateHertz,
              samples.allSatisfy(\.isFinite)
        else {
            throw MeetingTranscriptionRuntimeRouterError.invalidPacket
        }
        let encoding: MeetingTranscriptionAudioEncoding
        let bytes: Data
        if mode == .localChunked {
            encoding = .pcmFloat32LittleEndian
            bytes = samples.map(\.bitPattern.littleEndian).withUnsafeBytes { Data($0) }
        } else {
            encoding = .pcmSigned16LittleEndian
            let pcm = samples.map { sample -> Int16 in
                let scaled = Double(min(1, max(-1, sample))) * Double(Int16.max)
                return Int16(clamping: Int64(scaled.rounded()))
            }
            bytes = pcm.map(\.littleEndian).withUnsafeBytes { Data($0) }
        }
        return try MeetingNormalizedAudioPacket(
            operationID: operationID,
            sessionID: sessionID,
            trackID: source.trackID,
            source: source.transcriptionSource,
            sampleRange: MeetingCanonicalSampleRange(
                startFrame: sampleRange.startFrame,
                endFrame: sampleRange.endFrame,
                sampleRateHertz: sampleRange.sampleRateHertz
            ),
            encoding: encoding,
            sampleRateHertz: sampleRateHertz,
            channelCount: MeetingAudioFormat.channelCount,
            bytes: bytes,
            providerEpoch: providerEpoch
        )
    }

    func transcriptionContext(
        sessionID: UUID,
        keyterms: [String] = []
    ) throws -> MeetingTrackTranscriptionContextSnapshot {
        try MeetingTrackTranscriptionContextSnapshot(
            sessionID: sessionID,
            trackID: source.trackID,
            source: source.transcriptionSource,
            canonicalSampleRateHertz: sampleRateHertz,
            channelCount: MeetingAudioFormat.channelCount,
            startedAtMilliseconds: source.startedAtMilliseconds,
            keyterms: keyterms
        )
    }
}

enum MeetingStableOperationIdentity {
    static func uuid(sessionID: UUID, trackID: UUID, startFrame: Int64, endFrame: Int64) -> UUID {
        let source = Data("\(sessionID.uuidString.lowercased())|\(trackID.uuidString.lowercased())|\(startFrame)|\(endFrame)".utf8)
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_119
        for byte in source {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte)) &* 14_029_467_366_897_019_727
        }
        var bytes = withUnsafeBytes(of: first.bigEndian) { Array($0) }
        bytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian) { Array($0) })
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension MeetingAudioSourceIdentity {
    var transcriptionSource: MeetingTranscriptionSource {
        switch kind {
        case .microphone:
            .microphone
        case .systemAudio:
            .systemAudio
        case .importedAudio:
            .importedAudio
        }
    }
}
