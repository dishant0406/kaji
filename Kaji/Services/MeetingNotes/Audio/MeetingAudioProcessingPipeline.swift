import Foundation
import os

enum MeetingAudioPipelineDrainResult: Equatable {
    case finished
    case timedOut
    case cancelled
}

private final class MeetingAudioPipelineDrainRace: Sendable {
    private struct State {
        var result: MeetingAudioPipelineDrainResult?
        var continuation: CheckedContinuation<MeetingAudioPipelineDrainResult, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait() async -> MeetingAudioPipelineDrainResult {
        await withCheckedContinuation { continuation in
            let result = state.withLock { state -> MeetingAudioPipelineDrainResult? in
                if let result = state.result { return result }
                state.continuation = continuation
                return nil
            }
            if let result { continuation.resume(returning: result) }
        }
    }

    func resolve(_ result: MeetingAudioPipelineDrainResult) {
        let continuation = state.withLock { state -> CheckedContinuation<MeetingAudioPipelineDrainResult, Never>? in
            guard state.result == nil else { return nil }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
    }
}

actor MeetingAudioProcessingPipeline {
    typealias EventHandler = @Sendable (MeetingAudioPipelineEvent) async -> Void

    private let queue: MeetingAudioEventQueue
    private let configuration: MeetingAudioChunkConfiguration
    private let transcriptionRouter: MeetingTranscriptionRuntimeRouter
    private let transcriptionSessionID: UUID
    private let transcriptionMode: MeetingTranscriptionMode
    private let keyterms: [String]
    private let eventHandler: EventHandler
    private let resampler = MeetingAudioResampler()
    private var chunkers: [MeetingAudioSourceIdentity: MeetingAudioChunker] = [:]
    private var realtimePacketizers: [MeetingAudioSourceIdentity: MeetingRealtimeAudioPacketizer] = [:]
    private var worker: Task<Void, Never>?

    init(
        queue: MeetingAudioEventQueue,
        configuration: MeetingAudioChunkConfiguration,
        transcriptionRouter: MeetingTranscriptionRuntimeRouter,
        transcriptionSessionID: UUID,
        transcriptionMode: MeetingTranscriptionMode = .localChunked,
        keyterms: [String] = [],
        eventHandler: @escaping EventHandler
    ) {
        self.queue = queue
        self.configuration = configuration
        self.transcriptionRouter = transcriptionRouter
        self.transcriptionSessionID = transcriptionSessionID
        self.transcriptionMode = transcriptionMode
        self.keyterms = keyterms
        self.eventHandler = eventHandler
    }

    func start() {
        guard worker == nil else { return }
        worker = Task { await consume() }
    }

    func waitUntilFinished() async {
        await worker?.value
    }

    func waitUntilFinished(timeout: Duration) async -> MeetingAudioPipelineDrainResult {
        guard let activeWorker = worker else { return .finished }
        guard timeout > .zero else {
            activeWorker.cancel()
            worker = nil
            await queue.cancel()
            await transcriptionRouter.cancel()
            await activeWorker.value
            return .timedOut
        }
        let race = MeetingAudioPipelineDrainRace()
        let completionTask = Task {
            await activeWorker.value
            race.resolve(.finished)
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
                race.resolve(.timedOut)
            } catch {}
        }
        let result = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            race.resolve(.cancelled)
        }
        completionTask.cancel()
        timeoutTask.cancel()
        guard result != .finished else { return result }
        activeWorker.cancel()
        worker = nil
        await queue.cancel()
        await transcriptionRouter.cancel()
        await activeWorker.value
        return result
    }

    func cancel() async {
        let activeWorker = worker
        worker = nil
        activeWorker?.cancel()
        await queue.cancel()
        await transcriptionRouter.cancel()
        await activeWorker?.value
    }

    private func consume() async {
        do {
            while let event = try await queue.next() {
                try Task.checkCancellation()
                await process(event)
            }
            await flushAll()
            await transcriptionRouter.finish()
        } catch is CancellationError {
            await transcriptionRouter.cancel()
            return
        } catch {
            await transcriptionRouter.cancel()
            await emitFailure(error)
        }
    }

    private func process(_ event: MeetingAudioQueueEvent) async {
        switch event {
        case let .audio(buffer):
            await process(buffer)
        case let .gap(gap):
            await process(gap)
        case let .failure(failure):
            await eventHandler(.failure(failure))
        }
    }

    private func process(_ buffer: MeetingOwnedAudioBuffer) async {
        do {
            let converted = try resampler.convert(buffer)
            guard !converted.samples.isEmpty else { return }
            let chunks: [MeetingTranscriptionAudioChunk]
            if transcriptionMode == .cloudRealtime {
                var packetizer = try realtimePacketizer(for: buffer.source)
                chunks = try packetizer.append(converted)
                realtimePacketizers[buffer.source] = packetizer
            } else {
                var chunker = try chunker(for: buffer.source)
                chunks = try chunker.append(converted)
                chunkers[buffer.source] = chunker
            }
            await transcribe(chunks)
        } catch {
            let gap = MeetingAudioGap(buffer: buffer, reason: .conversionFailure)
            await process(gap)
        }
    }

    private func process(_ gap: MeetingAudioGap) async {
        do {
            if let tail = try resampler.finish(source: gap.source) {
                let tailChunks: [MeetingTranscriptionAudioChunk]
                if transcriptionMode == .cloudRealtime {
                    var packetizer = try realtimePacketizer(for: gap.source)
                    tailChunks = try packetizer.append(tail)
                    realtimePacketizers[gap.source] = packetizer
                } else {
                    var chunker = try chunker(for: gap.source)
                    tailChunks = try chunker.append(tail)
                    chunkers[gap.source] = chunker
                }
                await transcribe(tailChunks)
            }
            let chunks: [MeetingTranscriptionAudioChunk]
            if transcriptionMode == .cloudRealtime {
                var packetizer = try realtimePacketizer(for: gap.source)
                chunks = try packetizer.applyGap(gap)
                realtimePacketizers[gap.source] = packetizer
            } else {
                var chunker = try chunker(for: gap.source)
                chunks = try chunker.applyGap(gap)
                chunkers[gap.source] = chunker
            }
            await transcribe(chunks)
            await eventHandler(.gap(gap))
        } catch {
            await emitFailure(error)
        }
    }

    private func flushAll() async {
        let sources = Set(chunkers.keys).union(realtimePacketizers.keys).sorted {
            if $0.startedAtMilliseconds == $1.startedAtMilliseconds {
                return $0.trackID.uuidString < $1.trackID.uuidString
            }
            return $0.startedAtMilliseconds < $1.startedAtMilliseconds
        }
        for source in sources {
            do {
                if let tail = try resampler.finish(source: source) {
                    let tailChunks: [MeetingTranscriptionAudioChunk]
                    if transcriptionMode == .cloudRealtime {
                        var packetizer = try realtimePacketizer(for: source)
                        tailChunks = try packetizer.append(tail)
                        realtimePacketizers[source] = packetizer
                    } else {
                        var chunker = try chunker(for: source)
                        tailChunks = try chunker.append(tail)
                        chunkers[source] = chunker
                    }
                    await transcribe(tailChunks)
                }
                let chunks: [MeetingTranscriptionAudioChunk]
                if transcriptionMode == .cloudRealtime {
                    var packetizer = try realtimePacketizer(for: source)
                    chunks = try packetizer.flush()
                    realtimePacketizers[source] = packetizer
                } else {
                    var chunker = try chunker(for: source)
                    chunks = try chunker.flush()
                    chunkers[source] = chunker
                }
                await transcribe(chunks)
            } catch {
                await emitFailure(error)
            }
        }
    }

    private func transcribe(_ chunks: [MeetingTranscriptionAudioChunk]) async {
        for chunk in chunks {
            do {
                try await transcriptionRouter.submit(
                    chunk.normalizedPacket(sessionID: transcriptionSessionID, mode: transcriptionMode),
                    context: chunk.transcriptionContext(sessionID: transcriptionSessionID, keyterms: keyterms)
                )
            } catch is CancellationError {
                return
            } catch {
                await emitFailure(error)
            }
        }
    }

    private func chunker(for source: MeetingAudioSourceIdentity) throws -> MeetingAudioChunker {
        if let chunker = chunkers[source] { return chunker }
        return try MeetingAudioChunker(source: source, configuration: configuration)
    }

    private func realtimePacketizer(for source: MeetingAudioSourceIdentity) throws -> MeetingRealtimeAudioPacketizer {
        if let packetizer = realtimePacketizers[source] { return packetizer }
        return try MeetingRealtimeAudioPacketizer(source: source)
    }

    private func emitFailure(_ error: Error) async {
        let failure = MeetingAudioCaptureFailure(
            domain: "Kaji.MeetingAudio",
            code: 1,
            message: "Meeting audio processing failed."
        )
        await eventHandler(.failure(failure))
    }
}
